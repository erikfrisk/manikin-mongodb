manikin = require('./setup').requireSource('manikin-mongo')
should = require 'should'
mongojs = require 'mongojs'
_ = require 'underscore'
async = require 'async'

connstr = 'mongodb://localhost/manikin-test'

dropDatabase = (connStr, done) ->
  conn = mongojs.connect(connStr)
  conn.collectionNames (err, colls) ->
    throw err if err
    collNames = colls.map ({ name }) -> _(name.split('.')).last()
    async.forEach collNames.slice(1), conn.dropCollection, done

require('./manikin-spec').runTests(manikin, dropDatabase, 'mongodb://localhost/manikin-test')



## Injection tests
## ===============

describe "replacing find.exec", ->

  makeMongoose = (onExec) ->
    mongoose = require 'mongoose'
    _.extend {}, mongoose,
      createConnection: ->
        connection = mongoose.createConnection.apply(this, arguments)
        _.extend {}, connection,
          model: ->
            mod = connection.model.apply(this, arguments)
            _.extend {}, mod,
              find: -> _.extend mod.find.apply(this, arguments),
                exec: onExec



  it "should replace find.exec successfully", (done) ->
    mongoose = makeMongoose (callback) ->
      callback(null, [1,2,3])

    api = manikin.create(mongoose)

    models =
      user:
        fields:
          name: 'string'
          age: 'number'

    api.connect connstr, models, (err) ->
      should.not.exist err
      api.list 'user', {}, (err, data) ->
        should.not.exist err
        data.should.eql [1,2,3]
        done()



  it "should replace find.exec successfully", (done) ->
    mongoose = makeMongoose (callback) ->
      callback("something failed")

    api = manikin.create(mongoose)

    models =
      user:
        fields:
          name: 'string'
          age: 'number'

    api.connect connstr, models, (err) ->
      should.not.exist err
      api.list 'user', {}, (err, data) ->
        err.should.eql new Error()
        done()
