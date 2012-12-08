_ = require 'underscore'
should = require 'should'
tools = require('./setup').requireSource('manikin-tools')



it "should have the right methods", ->
  tools.should.have.keys [
    'desugar'
    'getMeta'
  ]



it "should support desugaring of models", ->
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



it "should support various different types", ->
  dataIn =
    surveys:
      fields:
        birth: 'date'
        count: 'number'
        name: 'string'
        done: 'boolean'
        various: 'mixed'
        question:
          type: 'hasOne'
          model: 'questions'
        qs:
          type: 'hasMany'
          model: 'questions'
        qs2:
          type: 'hasMany'
          model: 'questions'
          inverseName: 'inv'
        ne:
          type: 'nested'
          v1: 'number'
          v2: 'string'
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
        birth:    { type: 'date',    required: false, index: false, unique: false }
        count:    { type: 'number',  required: false, index: false, unique: false }
        name:     { type: 'string',  required: false, index: false, unique: false }
        done:     { type: 'boolean', required: false, index: false, unique: false }
        various:  { type: 'mixed' }
        question: { type: 'hasOne', model: 'questions' }
        qs:       { type: 'hasMany', model: 'questions', inverseName: 'qs' }
        qs2:      { type: 'hasMany', model: 'questions', inverseName: 'inv' }
        ne:       {
          type: 'nested'
          v1:     { type: 'number',  required: false, index: false, unique: false }
          v2:     { type: 'string',  required: false, index: false, unique: false }
        }
    questions:
      owners:
        survey: 'surveys'
      indirectOwners: {}
      fields:
        name: { type: 'string', required: false, index: false, unique: false }

  tools.desugar(dataIn).should.eql(dataOut)



it "should support indirect owners", ->
  dataIn =
    surveys: {}
    questions:
      owners:
        survey: 'surveys'
    answers:
      owners:
        question: 'questions'
    options:
      owners:
        answer: 'answers'

  dataOut =
    surveys:
      fields: {}
      owners: {}
      indirectOwners: {}
    questions:
      fields: {}
      owners: { survey: 'surveys' }
      indirectOwners: {}
    answers:
      fields: {}
      owners: { question: 'questions' }
      indirectOwners: { survey: 'surveys' }
    options:
      fields: {}
      owners: { answer: 'answers' }
      indirectOwners: { survey: 'surveys', question: 'questions' }

  tools.desugar(dataIn).should.eql(dataOut)



it "should support validations", ->
  f = (x) -> x.length > 5

  dataIn =
    questions:
      fields:
        name: { type: 'string', validate: f }

  dataOut =
    questions:
      fields:
        name: { type: 'string', required: false, unique: false, index: false, validate: f }
      owners: {}
      indirectOwners: {}

  tools.desugar(dataIn).should.eql(dataOut)



it "should support default values", ->
  dataIn =
    questions:
      fields:
        name: { type: 'string', default: 'hej' }

  dataOut =
    questions:
      fields:
        name: { type: 'string', required: false, unique: false, index: false, default: 'hej' }
      owners: {}
      indirectOwners: {}

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
      owners:
        company: 'companies'
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

    companies:
      owners: [{ plur: 'accounts', sing: 'account' }]
      owns: [{ name: 'customers', field: 'company' }]
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

    customers:
      owners: [{ plur: 'companies', sing: 'company' }]
      owns: []
      manyToMany: [{ ref: 'companies', name: 'at', inverseName: 'at' }]
      fields: [
        { name: 'account', readonly: true,  required: true,  type: 'string'  }
        { name: 'company', readonly: true,  required: true,  type: 'string'  }
        { name: 'id',      readonly: true,  required: false, type: 'string'  }
        { name: 'name',    readonly: false, required: false, type: 'string'  }
      ]
