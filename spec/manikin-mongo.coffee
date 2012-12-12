manikin = require('./setup').requireSource('manikin-mongo')
mongojs = require 'mongojs'
_ = require 'underscore'
async = require 'async'

dropDatabase = (connStr, done) ->
  conn = mongojs.connect(connStr)
  conn.collectionNames (err, colls) ->
    throw err if err
    collNames = colls.map ({ name }) -> _(name.split('.')).last()
    async.forEach collNames.slice(1), conn.dropCollection, done

require('./manikin-spec').runTests(manikin, dropDatabase, 'mongodb://localhost/manikin-test')
