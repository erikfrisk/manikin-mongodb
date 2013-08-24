if [ -z "$NODE_ENV" ]; then
  echo "Skipping coveralls"
else
  npm run coveralls | ./node_modules/coveralls/bin/coveralls.js
fi
