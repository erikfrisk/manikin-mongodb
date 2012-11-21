coffee -c -o lib src
mkdir -p test-coverage
rm -rf test-cov
coffee -c spec/*.coffee
jscoverage lib/ test-cov
SRC_DIR=test-cov mocha --reporter html-cov $1 > test-coverage/$2
rm spec/mocha.js
rm spec/manikin.js
rm -rf test-cov
open test-coverage/$2
