manikin = require('./setup').requireSource('manikin')
mongojs = require 'mongojs'
_ = require 'underscore'
async = require 'async'

dropDatabase = (connStr, done) ->
  conn = mongojs.connect(connStr)
  conn.collectionNames (err, colls) ->
    throw err if err
    collNames = colls.map ({ name }) -> _(name.split('.')).last()
    async.forEach collNames.slice(1), conn.dropCollection, done

require('./manikin').runTests(manikin, dropDatabase, 'mongodb://localhost/manikin-test')
