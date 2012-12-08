#!/bin/sh
coffee -co lib src
mkdir -p test-coverage
rm -rf test-cov
coffee -co spec-coverage spec/*.coffee
jscoverage lib/ test-cov
SRC_DIR=test-cov mocha --reporter html-cov spec-coverage/$1 > test-coverage/$2
rm -rf spec-coverage test-cov
open test-coverage/$2
