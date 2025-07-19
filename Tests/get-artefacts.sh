#!/bin/bash -x

RUN_ID=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
artefacts=(
  'quick-validation-results'
)

mkdir -p ./Artefacts
# shellcheck disable=SC2041
for artefact in "${artefacts[@]}"; do
  echo "Retrieving artefact: $artefact"
  mkdir -p ./Artefacts/run-"$RUN_ID"
  gh run download "$RUN_ID" --name "$artefact" --dir ./Artefacts/run-"$RUN_ID"
done