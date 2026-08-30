#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH
umask 077

fail() {
  printf '[dre-image-build] ERRO: %s\n' "$*" >&2
  exit 1
}

[[ "$#" -eq 4 ]] \
  || fail 'uso fechado: REMOTE_ROOT SOURCE_REVISION SOURCE_SHA256 BUILDKIT_SHA256'
readonly remote_root="$1"
readonly source_revision="$2"
readonly source_archive_sha256="$3"
readonly buildkit_archive_sha256="$4"
readonly source_archive="${remote_root}/source.tar"
readonly buildkit_archive="${remote_root}/buildkit.tar.gz"
readonly output_directory="${remote_root}/output"
readonly controller_lock='/run/lock/dre-deployctl.lock'
readonly blindou_lock='/run/lock/blindou-deployctl.lock'
readonly slot_lock='/run/lock/servidor-local-secondary-slot.lock'
readonly build_lock='/run/lock/dre-image-build.lock'

[[ "${EUID}" -eq 0 ]] || fail 'execute como root'
[[ "$(hostname)" == apiwpp ]] || fail 'hostname inesperado'
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || fail 'revisão-fonte inválida'
[[ "$source_archive_sha256" =~ ^[0-9a-f]{64}$ ]] || fail 'SHA do código inválido'
[[ "$buildkit_archive_sha256" =~ ^[0-9a-f]{64}$ ]] || fail 'SHA do BuildKit inválido'
[[ "$remote_root" == \
  "/home/apiadmin/dre-image-build-${source_revision:0:12}-"* ]] \
  || fail 'staging remoto fora do prefixo aprovado'
[[ "$remote_root" =~ ^/home/apiadmin/dre-image-build-[0-9a-f]{12}-[0-9]{8}T[0-9]{6}Z$ ]] \
  || fail 'staging remoto possui formato inválido'

for command in awk chmod chown cut date df find flock install ionice jq kill \
  mkdir mktemp mv nice nproc python3 rm seq sha256sum sleep stat tail tar tr; do
  command -v "$command" >/dev/null || fail "dependência ausente: ${command}"
done
[[ "$(nproc)" -ge 4 ]] || fail 'host possui menos de quatro CPUs'
memory_available="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
disk_available="$(df -B1 --output=avail /var/lib/rancher/k3s \
  | tail -n 1 | tr -d '[:space:]')"
[[ "$memory_available" =~ ^[0-9]+$ && "$memory_available" -ge 8388608 ]] \
  || fail 'build exige ao menos 8 GiB de memória disponível'
[[ "$disk_available" =~ ^[0-9]+$ && "$disk_available" -ge 64424509440 ]] \
  || fail 'build exige ao menos 60 GiB livres'

[[ -d "$remote_root" && ! -L "$remote_root" ]] \
  || fail 'staging remoto ausente ou simbólico'
[[ "$(stat -c '%U:%G:%a:%h' "$remote_root")" == 'apiadmin:apiadmin:700:2' ]] \
  || fail 'staging remoto possui ownership, modo ou links inseguros'
for source in "$source_archive" "$buildkit_archive"; do
  [[ -f "$source" && ! -L "$source" ]] \
    || fail "fonte ausente ou simbólica: ${source}"
  [[ "$(stat -c '%U:%G:%a:%h' "$source")" == 'apiadmin:apiadmin:600:1' ]] \
    || fail "fonte possui ownership, modo ou links inseguros: ${source}"
done
[[ "$(sha256sum "$source_archive" | cut -d' ' -f1)" == "$source_archive_sha256" ]] \
  || fail 'SHA-256 do código-fonte diverge'
[[ "$(sha256sum "$buildkit_archive" | cut -d' ' -f1)" == "$buildkit_archive_sha256" ]] \
  || fail 'SHA-256 do BuildKit diverge'
[[ ! -e "$output_directory" && ! -L "$output_directory" ]] \
  || fail 'diretório de saída já existe'

/usr/local/sbin/dre-deployctl status >/dev/null \
  || fail 'controlador DRE não está íntegro'
/usr/local/sbin/blindou-deployctl status >/dev/null \
  || fail 'Blindou não está íntegro'
/usr/local/sbin/secondary-slotctl verify >/dev/null \
  || fail 'slot secundário não está íntegro'

exec 6>"$build_lock"
chmod 0600 "$build_lock"
flock -n 6 || fail 'outro build DRE está em andamento'
exec 7>"$controller_lock"
flock -n 7 || fail 'operação DRE está em andamento'
exec 8>"$blindou_lock"
flock -n 8 || fail 'operação Blindou está em andamento'
[[ -f "$slot_lock" && ! -L "$slot_lock" ]] \
  || fail 'lock do slot secundário ausente ou inseguro'
exec 9<>"$slot_lock"
flock -n 9 || fail 'transição APIWPP/SaferWPP está em andamento'

work_directory="$(mktemp -d \
  "/var/tmp/dre-image-build.${source_revision:0:12}.XXXXXX")"
daemon_pid=''
daemon_log="${work_directory}/buildkitd.log"
cleanup() {
  local result="$?"
  trap - EXIT
  if [[ -n "$daemon_pid" ]]; then
    kill -TERM "$daemon_pid" >/dev/null 2>&1 || true
    wait "$daemon_pid" >/dev/null 2>&1 || true
  fi
  if [[ -f "$daemon_log" && ! -L "$daemon_log" ]]; then
    install -o apiadmin -g apiadmin -m 0600 -- "$daemon_log" \
      "${remote_root}/buildkitd.log" || true
  fi
  if [[ -n "$work_directory" && -d "$work_directory" \
      && "$work_directory" == /var/tmp/dre-image-build.* ]]; then
    rm -rf --one-file-system -- "$work_directory"
  fi
  exit "$result"
}
trap cleanup EXIT

install -o root -g root -m 0600 -- "$source_archive" \
  "${work_directory}/source.tar"
install -o root -g root -m 0600 -- "$buildkit_archive" \
  "${work_directory}/buildkit.tar.gz"
[[ "$(sha256sum "${work_directory}/source.tar" | cut -d' ' -f1)" \
    == "$source_archive_sha256" ]] || fail 'cópia root-owned do código diverge'
[[ "$(sha256sum "${work_directory}/buildkit.tar.gz" | cut -d' ' -f1)" \
    == "$buildkit_archive_sha256" ]] \
  || fail 'cópia root-owned do BuildKit diverge'

install -d -o root -g root -m 0700 \
  "${work_directory}/source" "${work_directory}/buildkit"
python3 - "${work_directory}/source.tar" \
  "${work_directory}/source" <<'PY'
from __future__ import annotations

import os
from pathlib import Path, PurePosixPath
import stat
import sys
import tarfile

archive = Path(sys.argv[1])
destination = Path(sys.argv[2]).resolve()
maximum_members = 8192
maximum_file_bytes = 64 * 1024 * 1024
maximum_total_bytes = 512 * 1024 * 1024


def validated_name(raw_name: str) -> str:
    path = PurePosixPath(raw_name)
    normalized = str(path)
    if (
        not raw_name
        or path.is_absolute()
        or normalized != raw_name.rstrip("/")
        or any(part in {"", ".", ".."} for part in path.parts)
        or any(part == ".git" for part in path.parts)
        or path.name == ".env"
    ):
        raise SystemExit(f"membro inválido no archive-fonte: {raw_name!r}")
    return normalized


with tarfile.open(archive, mode="r:") as release:
    members = release.getmembers()
    if not members or len(members) > maximum_members:
        raise SystemExit("quantidade de membros do archive-fonte é inválida")
    total_bytes = 0
    regular_files: list[tuple[tarfile.TarInfo, str]] = []
    for member in members:
        name = validated_name(member.name)
        if member.isdir():
            continue
        if not member.isreg():
            raise SystemExit(f"tipo inesperado no archive-fonte: {name}")
        if member.size < 0 or member.size > maximum_file_bytes:
            raise SystemExit(f"tamanho inválido no archive-fonte: {name}")
        total_bytes += member.size
        if total_bytes > maximum_total_bytes:
            raise SystemExit("archive-fonte excede o limite descompactado")
        regular_files.append((member, name))

    required = {
        "backend/Dockerfile.release",
        "backend/Cargo.lock",
        "infra/postgres/Dockerfile.k3s",
        "tests/Dockerfile.e2e",
    }
    names = {name for _, name in regular_files}
    if not required.issubset(names):
        raise SystemExit("archive-fonte não contém os Dockerfiles/lockfile obrigatórios")

    for member, name in regular_files:
        target = destination.joinpath(*PurePosixPath(name).parts)
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        source = release.extractfile(member)
        if source is None:
            raise SystemExit(f"não foi possível abrir membro regular: {name}")
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC
        flags |= getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(target, flags, 0o600)
        try:
            with source:
                while chunk := source.read(1024 * 1024):
                    view = memoryview(chunk)
                    while view:
                        written = os.write(descriptor, view)
                        if written <= 0:
                            raise SystemExit(f"gravação interrompida: {name}")
                        view = view[written:]
            os.fsync(descriptor)
            metadata = os.fstat(descriptor)
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
                raise SystemExit(f"alvo extraído possui tipo inseguro: {name}")
        finally:
            os.close(descriptor)
PY

python3 - "${work_directory}/buildkit.tar.gz" <<'PY'
from pathlib import Path, PurePosixPath
import sys
import tarfile

archive = Path(sys.argv[1])
allowed_files = {
    "bin/buildctl",
    "bin/buildkit-cni-bridge",
    "bin/buildkit-cni-firewall",
    "bin/buildkit-cni-host-local",
    "bin/buildkit-cni-loopback",
    "bin/buildkit-qemu-aarch64",
    "bin/buildkit-qemu-arm",
    "bin/buildkit-qemu-i386",
    "bin/buildkit-qemu-ppc64le",
    "bin/buildkit-qemu-riscv64",
    "bin/buildkit-qemu-s390x",
    "bin/buildkit-runc",
    "bin/buildkitd",
}
maximum_buildkit_file_bytes = 96 * 1024 * 1024
maximum_buildkit_total_bytes = 256 * 1024 * 1024
with tarfile.open(archive, mode="r:gz") as release:
    members = release.getmembers()
    regular = set()
    total_bytes = 0
    for member in members:
        path = PurePosixPath(member.name)
        name = str(path)
        if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
            raise SystemExit("caminho inválido no BuildKit")
        if member.isdir():
            if name != "bin":
                raise SystemExit("diretório inesperado no BuildKit")
            continue
        if not member.isreg() or name not in allowed_files:
            raise SystemExit("membro inesperado no BuildKit")
        if member.size <= 0 or member.size > maximum_buildkit_file_bytes:
            raise SystemExit("tamanho inválido no BuildKit")
        total_bytes += member.size
        if total_bytes > maximum_buildkit_total_bytes:
            raise SystemExit("BuildKit excede o limite total descompactado")
        regular.add(name)
    if regular != allowed_files:
        raise SystemExit("inventário do BuildKit diverge")
PY
tar -xzf "${work_directory}/buildkit.tar.gz" \
  -C "${work_directory}/buildkit"
chmod 0700 "${work_directory}/buildkit/bin/"*

readonly buildkitd="${work_directory}/buildkit/bin/buildkitd"
readonly buildctl="${work_directory}/buildkit/bin/buildctl"
readonly socket="unix://${work_directory}/buildkitd.sock"
nice -n 10 ionice -c 2 -n 7 "$buildkitd" \
  --root "${work_directory}/buildkit-state" \
  --addr "$socket" \
  --containerd-worker=false \
  --oci-worker=true \
  --oci-worker-snapshotter=native \
  --oci-worker-net=bridge \
  --oci-worker-binary "${work_directory}/buildkit/bin/buildkit-runc" \
  --oci-worker-gc=false \
  --oci-max-parallelism=2 \
  >"$daemon_log" 2>&1 &
daemon_pid="$!"

ready=false
for _ in $(seq 1 90); do
  if "$buildctl" --addr "$socket" debug workers >/dev/null 2>&1; then
    ready=true
    break
  fi
  kill -0 "$daemon_pid" >/dev/null 2>&1 \
    || fail 'BuildKit encerrou durante a inicialização'
  sleep 1
done
[[ "$ready" == true ]] || fail 'BuildKit não ficou pronto em 90 segundos'

install -d -o root -g root -m 0700 "${work_directory}/output"
build_image() {
  local component="$1" dockerfile="$2" target="$3" image_name="$4"
  local -a options=(
    --addr "$socket"
    build
    --progress plain
    --frontend dockerfile.v0
    --local "context=${work_directory}/source"
    --local "dockerfile=${work_directory}/source"
    --opt "filename=${dockerfile}"
    --opt 'platform=linux/amd64'
    --metadata-file "${work_directory}/output/${component}.metadata.json"
    --output "type=oci,name=${image_name}:git-${source_revision:0:12},dest=${work_directory}/output/${component}.oci.tar,oci-mediatypes=true,compression=gzip,force-compression=true"
  )
  if [[ -n "$target" ]]; then
    options+=(--opt "target=${target}")
  fi
  nice -n 10 ionice -c 2 -n 7 "$buildctl" "${options[@]}"
}

build_image rust backend/Dockerfile.release app ghcr.io/gleisonsette/dre-app
build_image postgres infra/postgres/Dockerfile.k3s '' \
  ghcr.io/gleisonsette/dre-postgres
build_image validation tests/Dockerfile.e2e '' \
  ghcr.io/gleisonsette/dre-validation-runner

for component in rust postgres validation; do
  [[ -s "${work_directory}/output/${component}.oci.tar" \
      && -s "${work_directory}/output/${component}.metadata.json" ]] \
    || fail "artefato OCI ausente: ${component}"
done
(cd "${work_directory}/output" && sha256sum \
  rust.oci.tar postgres.oci.tar validation.oci.tar \
  rust.metadata.json postgres.metadata.json validation.metadata.json \
  >SHA256SUMS)
jq -n \
  --arg source_revision "$source_revision" \
  --arg source_archive_sha256 "$source_archive_sha256" \
  --arg buildkit_archive_sha256 "$buildkit_archive_sha256" \
  --arg completed_at_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{schema:1,status:"passed",source_revision:$source_revision,source_archive_sha256:$source_archive_sha256,buildkit:{version:"v0.32.2",archive_sha256:$buildkit_archive_sha256},platform:"linux/amd64",components:["rust","postgres","validation"],completed_at_utc:$completed_at_utc}' \
  >"${work_directory}/output/build-receipt.json"

mv -- "${work_directory}/output" "$output_directory"
chown -R apiadmin:apiadmin "$output_directory"
find "$output_directory" -type d -exec chmod 0700 {} +
find "$output_directory" -type f -exec chmod 0600 {} +

flock --unlock 9
flock --unlock 8
flock --unlock 7
flock --unlock 6
exec 9>&-
exec 8>&-
exec 7>&-
exec 6>&-

/usr/local/sbin/dre-deployctl status >/dev/null \
  || fail 'controlador DRE divergiu após o build'
/usr/local/sbin/blindou-deployctl status >/dev/null \
  || fail 'Blindou divergiu após o build'
/usr/local/sbin/secondary-slotctl verify >/dev/null \
  || fail 'slot secundário divergiu após o build'

printf 'dre_image_build=passed source_revision=%s output=%s\n' \
  "$source_revision" "$output_directory"
