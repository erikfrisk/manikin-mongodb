jscov = require 'jscov'
manikinSpec = require 'manikin'
mongojs = require 'mongojs'
_ = require 'underscore'
async = require 'async'

locals = require './locals'

manikin = require jscov.cover('..', 'lib', 'manikin-mongo')

getConn = do ->
  conns = {}
  (connStr) ->
    conns[connStr] = mongojs.connect(connStr) if !conns[connStr]?
    conns[connStr]

dropDatabase = (connStr, done) ->
  conn = getConn(connStr)
  conn.collectionNames (err, colls) ->
    throw err if err
    collNames = colls.map ({ name }) -> _(name.split('.')).last()
    async.forEach collNames.slice(1), conn.dropCollection.bind(conn), done

locals.runTests(manikin, dropDatabase, 'mongodb://localhost/manikin-test')
manikinSpec.runTests(manikin, dropDatabase, 'mongodb://localhost/manikin-test')
