#!/usr/bin/env bash
# Checks the Terraform code without any cloud access: formatting, then init without a backend
# and validate in every directory that contains .tf files. CI runs it on every change;
# run it locally before pushing too:
#   ./scripts/terraform-validate.sh            whole repository
#   ./scripts/terraform-validate.sh terraform  a single directory
#
# Convention: a directory under modules/ is a child module. Every other one (bootstrap,
# environments) is a root module and must commit its .terraform.lock.hcl: init fails if the
# lock file is missing or no longer matches the required providers.
set -uo pipefail

root="${1:-.}"
dirs=()
while IFS= read -r dir; do
  dirs+=("$dir")
done < <(find "$root" -name '*.tf' -not -path '*/.terraform/*' -not -path '*/node_modules/*' -exec dirname {} \; | sort -u)

if [ ${#dirs[@]} -eq 0 ]; then
  echo "No Terraform files under $root: nothing to validate."
  exit 0
fi

failures=0

echo "== terraform fmt -check"
if ! terraform fmt -check -recursive -diff "$root"; then
  echo "Formatting issues: run terraform fmt -recursive and commit the result."
  failures=$((failures + 1))
fi

init_without_backend() {
  case "$1" in
    */modules/*) terraform -chdir="$1" init -backend=false -input=false -no-color ;;
    *) terraform -chdir="$1" init -backend=false -input=false -no-color -lockfile=readonly ;;
  esac
}

for dir in "${dirs[@]}"; do
  echo "== $dir"
  if ! output=$(init_without_backend "$dir" 2>&1); then
    echo "$output"
    echo "init failed. For a root module, run terraform init and commit .terraform.lock.hcl."
    failures=$((failures + 1))
    continue
  fi
  if ! terraform -chdir="$dir" validate -no-color; then
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed."
  exit 1
fi
echo "All checks passed. Directories checked: ${#dirs[@]}."
