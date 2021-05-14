#! /bin/bash
if [ ! $1 ]; then echo "Please input contract name"; exit 1; fi
if [ -e "flatten-contracts" ]; then rm -rf "flatten-contracts"; fi
mkdir "flatten-contract";
touch "flatten-contract/$1";

npx truffle-flattener "./contracts/$1" > "./flatten-contract/$1"