manikin = require '../lib/manikin'
assert = require 'assert'
should = require 'should'
async = require 'async'


it "should have the right methods", ->
  api = manikin.create()
  api.should.have.keys [
    'ObjectId'
    'isValidId'
    'connect'
    'list'
    'getOne'
    'delOne'
    'putOne'
    'post'
    'delMany'
    'postMany'
    'getMany'
    'getManyBackwards'
    'defModel'
    'getMetaFields'
    'getOwners'
    'getOwnedModels'
    'getManyToMany'
    'getModels'
  ]



it "should allow model definitions", ->
  api = manikin.create()

  api.defModel 'surveys',
    owners: {}
    fields: {}

  api.defModel 'questions',
    owners:
      survey: 'surveys'
    fields: {}

  api.getModels().should.eql ['surveys', 'questions']



it "should not be ok to post without speicfiying the owner", (done) ->
  api = manikin.create()

  api.defModel 'accounts',
    owners: {}
    fields:
      name: { type: 'string', default: '' }

  api.defModel 'companies',
    owners:
      account: 'accounts'
    fields:
      name: { type: 'string', default: '' }
      orgnr: { type: 'string', default: '' }

  api.connect 'mongodb://localhost/manikin-test-1', (err) ->
    should.not.exist err
    api.post 'accounts', { name: 'a1' }, (err, account) ->
      should.not.exist err
      account.should.have.keys ['name', 'id']
      api.post 'companies', { name: 'n', orgnr: 'nbr' }, (err, company) ->
        should.exist err # expect something more precise here...
        done()



it "should allow custom validators", (done) ->
  api = manikin.create()

  api.defModel 'pizzas',
    owners: {}
    fields:
      name:
        type: 'string'
        validate: (apiRef, value, callback) ->
          api.should.eql apiRef
          callback(value.length % 2 == 0)

  indata = [
    name: 'jakob'
    response: 'something wrong'
  ,
    name: 'tobias'
    response: null
  ]

  api.connect 'mongodb://localhost/manikin-test-2', (err) ->
    should.not.exist err
    async.forEach indata, (d, callback) ->
      api.post 'pizzas', { name: d.name }, (err, res) ->
        if d.response != null
          err.message.should.eql 'Validation failed'
          err.errors.name.path.should.eql 'name'
        callback()
    , done



it "should introduce redundant references to all ancestors", (done) ->
  api = manikin.create()

  api.defModel 'accounts',
    owners: {}
    fields:
      name: { type: 'string', default: '' }

  api.defModel 'companies',
    owners:
      account: 'accounts'
    fields:
      name: { type: 'string', default: '' }
      orgnr: { type: 'string', default: '' }

  api.defModel 'contacts',
    owners:
      company: 'companies'
    fields:
      email: { type: 'string', default: '' }
      phone: { type: 'string', default: '' }

  api.defModel 'pets',
    owners:
      contact: 'contacts'
    fields:
      race: { type: 'string', default: '' }

  api.connect 'mongodb://localhost/manikin-test-3', (err) ->
    should.not.exist err
    api.post 'accounts', { name: 'a1', bullshit: 123 }, (err, account) ->
      should.not.exist err
      account.should.have.keys ['name', 'id']
      api.post 'companies', { name: 'n', orgnr: 'nbr', account: account.id }, (err, company) ->
        should.not.exist err
        company.should.have.keys ['id', 'name', 'orgnr', 'account']
        api.post 'contacts', { email: '@', phone: '112', company: company.id }, (err, contact) ->
          should.not.exist err
          contact.should.have.keys ['id', 'email', 'phone', 'account', 'company']
          api.post 'pets', { race: 'dog', contact: contact.id }, (err, pet) ->
            should.not.exist err
            pet.should.have.keys ['id', 'race', 'account', 'company', 'contact']
            done()
