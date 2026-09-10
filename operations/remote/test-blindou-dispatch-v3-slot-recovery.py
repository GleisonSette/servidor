#!/usr/bin/env python3
"""Prova de bloqueio e recriação de slot em PostgreSQL 18 descartável."""

from pathlib import Path
import os
import re
import json
import select
import subprocess
import tempfile


def main() -> None:
    if os.geteuid() == 0:
        raise SystemExit("O teste exige usuário sem privilégio.")
    binaries = Path("/usr/lib/postgresql/18/bin")
    source = globals().get("CONTROLLER_SOURCE")
    if source is None:
        source = (Path(__file__).parent / "blindou-deployctl").read_text(encoding="utf-8")
    function = source.split("recreate_empty_dispatch_v3_slot_locked() {", 1)[1].split("\n}\n", 1)[0]
    recovery_sql = function.split("<<'SQL'\n", 1)[1].split("\nSQL", 1)[0]
    tables = sorted(set(re.findall(r"FROM ((?:public|blindou_cdc_state)\.[a-z0-9_]+)", recovery_sql)))
    assert len(tables) == 14, "Inventário de provas incompleto"
    environment = {"PATH": "/usr/bin:/bin", "LC_ALL": "C"}
    with tempfile.TemporaryDirectory(
        prefix="blindou-build-slot-recovery-", dir="/home/apiadmin"
    ) as temporary:
        root = Path(temporary)
        data = root / "data"
        socket = root / "socket"
        socket.mkdir(mode=0o700)

        def run(binary: str, *args: str, sql: str | None = None, refusal: bool = False) -> str:
            process = subprocess.run(
                [str(binaries / binary), *args], input=sql, text=True,
                capture_output=True, timeout=60, env=environment, check=False,
            )
            if refusal:
                if not process.returncode:
                    raise RuntimeError("Operação negativa foi aceita")
                return process.stdout + process.stderr
            if process.returncode:
                raise RuntimeError(f"{binary}: {process.stderr}")
            return process.stdout

        run("initdb", "-D", str(data), "--auth=trust", "--no-locale", "--no-sync")
        options = (
            f"-c listen_addresses='' -c unix_socket_directories='{socket}' "
            "-c shared_buffers=16MB -c max_connections=8 -c max_wal_senders=1 "
            "-c wal_level=logical -c max_replication_slots=1 "
            "-c min_wal_size=32MB -c max_wal_size=64MB -c max_slot_wal_keep_size=16MB"
        )
        try:
            run("pg_ctl", "-D", str(data), "-l", str(root / "postgres.log"), "-o", options, "-w", "start")
            run("createdb", "-h", str(socket), "blindou")
            arguments = ("-X", "-h", str(socket), "-d", "blindou", "-Atq", "-v", "ON_ERROR_STOP=1")
            setup = "CREATE SCHEMA blindou_cdc_state;\n"
            setup += "\n".join(f"CREATE TABLE {name}(engine_version integer);" for name in tables)
            setup += "\nCREATE TABLE public.unmonitored(id integer);\n"
            run("psql", *arguments, sql=setup)
            name = "blindou_dispatch_v3_outbox_slot"
            original_lsn = run("psql", *arguments, sql=f"SELECT lsn FROM pg_create_logical_replication_slot('{name}', 'pgoutput');").strip()
            recovery_arguments = (*arguments, "-v", f"original_lsn={original_lsn}", "-v", "allow_missing=false")
            run("psql", *recovery_arguments, sql=recovery_sql, refusal=True)
            # WAL sintético de tabela fora da publicação; nenhuma conexão operacional.
            for _ in range(5):
                run("psql", *arguments, sql="INSERT INTO unmonitored VALUES(1);\nSELECT pg_switch_wal();\n")
            run("psql", *arguments, sql="CHECKPOINT;")
            reason = run("psql", *arguments, sql=f"SELECT invalidation_reason FROM pg_replication_slots WHERE slot_name='{name}';").strip()
            assert reason == "wal_removed", reason
            diagnostic_function = source.split("diagnose_dispatch_v3_logical_slot() {", 1)[1].split("\n}\n", 1)[0]
            diagnostic_sql = diagnostic_function.split("<<'SQL'\n", 1)[1].split("\nSQL", 1)[0]
            diagnostic = json.loads(run("psql", *arguments, sql=diagnostic_sql))
            assert diagnostic["slot"]["invalidation_reason"] == "wal_removed"
            assert not any(diagnostic["rows_present"].values())
            for table in tables:
                run("psql", *arguments, sql=f"INSERT INTO {table} VALUES(3);")
                run("psql", *recovery_arguments, sql=recovery_sql, refusal=True)
                unchanged = run("psql", *arguments, sql=f"SELECT confirmed_flush_lsn FROM pg_replication_slots WHERE slot_name='{name}';").strip()
                assert unchanged == original_lsn
                run("psql", *arguments, sql=f"DELETE FROM {table};")
            # Escrita concorrente impede a aquisição do lock, sem remover o slot.
            writer = subprocess.Popen(
                [str(binaries / "psql"), *arguments], stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=environment,
            )
            try:
                writer.stdin.write("BEGIN; INSERT INTO public.dispatch_outbox_v3 VALUES(3); SELECT 'held';\n")
                writer.stdin.flush()
                if not select.select([writer.stdout], [], [], 10)[0]:
                    raise RuntimeError("Escritor sintético não respondeu em dez segundos")
                assert writer.stdout.readline().strip() == "held"
                refusal = run("psql", *recovery_arguments, sql=recovery_sql, refusal=True)
                assert "lock timeout" in refusal
                writer.stdin.write("ROLLBACK;\n")
                writer.stdin.flush()
                writer.communicate(timeout=10)
            finally:
                if writer.poll() is None:
                    writer.kill()
                    writer.communicate(timeout=10)
            run("psql", *arguments, "-v", "original_lsn=0/1", "-v", "allow_missing=false", sql=recovery_sql, refusal=True)
            result = run("psql", *recovery_arguments, sql=recovery_sql)
            assert name in result
            healthy = run("psql", *arguments, sql=f"SELECT invalidation_reason IS NULL FROM pg_replication_slots WHERE slot_name='{name}';").strip()
            assert healthy == "t"
            # A mesma entrada não apaga um slot que já ficou válido.
            run("psql", *recovery_arguments, sql=recovery_sql, refusal=True)
            run("psql", *arguments, sql=f"SELECT pg_drop_replication_slot('{name}');")
            run("psql", *recovery_arguments, sql=recovery_sql, refusal=True)
            result = run("psql", *arguments, "-v", f"original_lsn={original_lsn}", "-v", "allow_missing=true", sql=recovery_sql)
            assert name in result
            print("slot_recovery_postgres18=passed positive=3 refusals=19 tables=14 concurrent_writer=preserved")
        finally:
            run("pg_ctl", "-D", str(data), "-m", "immediate", "-w", "stop")


if __name__ == "__main__":
    main()
