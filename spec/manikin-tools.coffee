_ = require 'underscore'
should = require 'should'
tools = require('./setup').requireSource('manikin-tools')



it "should have the right methods", ->
  tools.should.have.keys [
    'desugar'
    'getMeta'
  ]



it "should allow model definitions in bulk", ->
  dataIn =
    surveys:
      fields:
        birth: 'date'
        count: { type: 'number', unique: true }
    questions:
      owners:
        survey: 'surveys'
      fields:
        name: 'string'

  dataOut =
    surveys:
      owners: {}
      indirectOwners: {}
      fields:
        birth: { type: 'date', required: false, index: false, unique: false }
        count: { type: 'number', required: false, index: false, unique: true }
    questions:
      owners:
        survey: 'surveys'
      indirectOwners: {}
      fields:
        name: { type: 'string', required: false, index: false, unique: false }

  tools.desugar(dataIn).should.eql(dataOut)



it "should fail if a field is missing its type", ->
  (->
    tools.desugar
      some_model:
        fields:
          name: { unique: true }
          age: { type: 'string', unique: true }
          whatever: { unique: true }
  ).should.throw('must assign a type: name')



it "should throw exceptions for invalid types", ->
  (->
    tools.desugar
      some_model:
        fields:
          name: 'an-invalid-type'
  ).should.throw('Invalid type: an-invalid-type')



it "should provide an interface for meta data", ->
  desugared = tools.desugar
    accounts:
      owners: {}
      fields:
        name: { type: 'string', default: '' }

    companies:
      owners:
        account: 'accounts'
      fields:
        name: { type: 'string', default: '' }
        orgnr: { type: 'string', default: '' }

    customers:
      fields:
        name: { type: 'string' }
        at: { type: 'hasMany', model: 'companies' }

  tools.getMeta(desugared).should.eql
    accounts:
      owners: []
      owns: [{ name: 'companies', field: 'account' }]
      manyToMany: []
      fields: [
        name: 'id'
        readonly: true
        required: false
        type: 'string'
      ,
        name: 'name'
        readonly: false
        required: false
        type: 'string'
      ]

    customers:
      owners: []
      owns: []
      manyToMany: [{ ref: 'companies', name: 'at', inverseName: 'at' }]  
      fields: [
        { name: 'id',   readonly: true,  required: false, type: 'string'  }
        { name: 'name', readonly: false, required: false, type: 'string'  }
      ]

    companies:
      owners: [{ plur: 'accounts', sing: 'account' }]
      owns: []
      manyToMany: [{ ref: 'customers', name: 'at', inverseName: 'at' }]
      fields: [
        name: 'account'
        readonly: true
        required: true
        type: 'string'
      ,
        name: 'id'
        readonly: true
        required: false
        type: 'string'
      ,
        name: 'name'
        readonly: false
        required: false
        type: 'string'
      ,
        name: 'orgnr'
        readonly: false
        required: false
        type: 'string'
      ]
