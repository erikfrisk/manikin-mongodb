manikin = require('./setup').requireSource('manikin')
mongojs = require 'mongojs'

dropDatabase = (connStr, done) ->
  mongojs.connect(connStr).dropDatabase done

connectionString = 'mongodb://localhost/manikin-test'

require('../spec/manikin').runTests(manikin, dropDatabase, connectionString)
