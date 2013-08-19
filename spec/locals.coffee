_ = require 'underscore'
async = require 'async'
should = require 'should'

exports.runTests = (manikin, dropDatabase, connectionData) ->

  noErr = (f) -> (err, rest...) ->
    throw err if err?
    f(rest...)

  beforeEach (done) ->
    dropDatabase(connectionData, done)

  after (done) ->
    dropDatabase(connectionData, done)

  it 'blaha', (done) ->

    model =
      operators:
        fields:
          name: 'string'
      assignments:
        owners: { operator: 'operators' }
        fields:
          localAssignmentId: 'number'
          name: 'string'

    api = manikin.create()
    api.connect connectionData, model, noErr ->
      api.post 'operators', { name: 'op1' }, noErr (op1) ->
        api.post 'operators', { name: 'op2' }, noErr (op2) ->
          api.post 'assignments', { operator: op1.id, name: 'ass1', localAssignmentId: 111 }, noErr (ass1) ->
            api.post 'assignments', { operator: op2.id, name: 'ass2', localAssignmentId: 222 }, noErr (ass2) ->
              api.getOne 'assignments', { filter: { operator: op1.id, localAssignmentId: 111 } }, noErr (res1) ->
                api.getOne 'assignments', { filter: { operator: op2.id, localAssignmentId: 222 } }, noErr (res2) ->
                  res1.name.should.eql 'ass1'
                  res2.name.should.eql 'ass2'
                  done()
