if [ -z "$TRAVIS_JOB_ID" ]; then
  echo "Skipping coveralls"
else
  npm run coveralls | ./node_modules/coveralls/bin/coveralls.js src
fi
