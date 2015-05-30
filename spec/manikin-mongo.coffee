runr = require 'runr'
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

getItUp = do ->
  upAlready = false
  (callback) ->
    return callback() if upAlready
    runr.up 'mongodb', {}, ->
      upAlready = true
      callback()

dropDatabase = do ->
  (connStr, done) ->
    getItUp ->
      conn = getConn(connStr)
      conn.collectionNames (err, colls) ->
        throw err if err
        collNames = colls.map ({ name }) -> _(name.split('.')).last()
        async.forEach collNames.slice(1), (collName, callback) ->
          f = conn.dropCollection.bind(conn)
          f collName, (err, rest...) ->
            if !err || err?.errmsg == 'ns not found'
              callback(null, rest...)
            else
              callback(err, rest...)
        , done

locals.runTests(manikin, dropDatabase, 'mongodb://localhost/manikin-test')
manikinSpec.runTests(manikin, dropDatabase, 'mongodb://localhost/manikin-test')
