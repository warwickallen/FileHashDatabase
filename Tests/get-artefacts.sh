#!/bin/bash

RUN_ID=$1
if [ -z "$RUN_ID" ]; then
  echo "No run ID provided, using latest run"
  RUN_ID=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
  echo "Using run ID: $RUN_ID"
fi

artefacts=(
  'quick-validation-results'
)

repo_dir=$(pwd)
while [ ! -d "$repo_dir/.git" ]; do
  repo_dir=$(dirname "$repo_dir")
done
artefacts_dir="$repo_dir/Tests/Artefacts/run-$RUN_ID"
ln -svf "$artefacts_dir" "$repo_dir/Tests/Artefacts/latest"

mkdir -p "$artefacts_dir"
# shellcheck disable=SC2041
for artefact in "${artefacts[@]}"; do
  echo "Retrieving artefact: $artefact"
  mkdir -p "$artefacts_dir"
  gh run download "$RUN_ID" --name "$artefact" --dir "$artefacts_dir"
done

echo "Artefacts downloaded to: $artefacts_dir"
echo "Latest artefacts are linked to: $repo_dir/Tests/Artefacts/latest"