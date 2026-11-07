#!/usr/bin/env bash

source common.sh

TODO_NixOS

needLocalStore "'--external-builders' can’t be used with the daemon"

expr="$TEST_ROOT/expr.nix"
cat > "$expr" <<EOF
with import ${config_nix};
mkDerivation {
  name = "external";
  system = "x68_46-xunil";
  buildCommand = ''
    echo xyzzy
    printf foo > \$out
  '';
}
EOF

external_builder="$TEST_ROOT/external-builder.sh"
cat > "$external_builder" <<EOF
#! $SHELL -e

PATH=${PATH@Q}

[[ "\$1" = bla ]]

system="\$(jq -r .system < "\$2")"
builder="\$(jq -r .builder < "\$2")"
args="\$(jq -r '.args | join(" ")' < "\$2")"
export buildCommand="\$(jq -r .env.buildCommand < "\$2")"
export out="\$(jq -r .env.out < "\$2")"
[[ \$system = x68_46-xunil ]]

printf "\2\n"

# In a real external builder, we would now call something like qemu to emulate the system.
"\$builder" \$args

printf bar >> \$out
EOF
chmod +x "$external_builder"

nix build -L --file "$expr" --out-link "$TEST_ROOT/result" \
  --extra-experimental-features external-builders \
  --external-builders "[{\"systems\": [\"x68_46-xunil\"], \"args\": [\"bla\"], \"program\": \"$external_builder\"}]"

[[ $(cat "$TEST_ROOT/result") = foobar ]]

# A derivation requiring a system feature, for the handler-matching cases below.
# Each case gets its own name: once an output is valid, a later build of the
# same derivation succeeds without consulting any handler.
featureExpr() {
  cat > "$TEST_ROOT/$1.nix" <<EOF2
with import ${config_nix};
mkDerivation {
  name = "$1";
  system = "x68_46-xunil";
  requiredSystemFeatures = [ "nonstandard-feature" ];
  buildCommand = ''
    printf foo > \$out
  '';
}
EOF2
}

buildWithHandler() {
  local expr="$1" handler="$2"
  nix build -L --file "$TEST_ROOT/$expr.nix" --out-link "$TEST_ROOT/result-$expr" \
    --extra-experimental-features external-builders \
    --external-builders "[{\"systems\": [\"x68_46-xunil\"], \"args\": [\"bla\"], \"program\": \"$external_builder\"$handler}]"
}

# excludeFeatures: the handler is skipped, so the derivation falls through to
# the normal local-build path and is rejected there for the missing feature,
# rather than being dispatched to a builder that cannot serve it.
featureExpr external-excluded
expectStderr 1 buildWithHandler external-excluded ', "excludeFeatures": ["nonstandard-feature"]' \
  | grepQuiet "missing system features"

# features: an allow-list that does not cover the requirement, same outcome.
featureExpr external-allow-miss
expectStderr 1 buildWithHandler external-allow-miss ', "features": ["some-other-feature"]' \
  | grepQuiet "missing system features"

# features: an allow-list that does cover it, so the handler runs.
featureExpr external-allow-hit
buildWithHandler external-allow-hit ', "features": ["nonstandard-feature"]'
[[ $(cat "$TEST_ROOT/result-external-allow-hit") = foobar ]]

# No feature keys at all: unchanged behaviour, the handler takes everything
# for its systems.
featureExpr external-nofeatures
buildWithHandler external-nofeatures ''
[[ $(cat "$TEST_ROOT/result-external-nofeatures") = foobar ]]
