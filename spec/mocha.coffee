manikin = require '../lib/manikin'
assert = require 'assert'
should = require 'should'

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

  api.connect 'mongodb://localhost/manikin-test', (err) ->
    should.not.exist err
    api.post 'accounts', { name: 'a1' }, (err, account) ->
      should.not.exist err
      account.should.have.keys ['name', 'id']
      api.post 'companies', { name: 'n', orgnr: 'nbr' }, (err, company) ->
        should.exist err # expect something more precise here...
        done()






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

  api.connect 'mongodb://localhost/manikin-test', (err) ->
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
