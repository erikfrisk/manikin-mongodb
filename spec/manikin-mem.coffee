manikin = require('./setup').requireSource('manikin-mem')

database = {}

dropDatabase = (db, done) ->
  Object.keys(db).forEach (key) ->
    delete db[key]
  done()

require('./manikin').runTests(manikin, dropDatabase, database)
