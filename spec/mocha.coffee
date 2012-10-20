manikin = require '../lib/manikin'
mongojs = require 'mongojs'
assert = require 'assert'
should = require 'should'
async = require 'async'
_ = require 'underscore'



it "should have the right methods", ->
  api = manikin.create()
  api.should.have.keys [
    # definition
    'defModel'
    'defModels'

    # meta-methods
    'getModels'
    'getMeta'

    # support-methods
    'isValidId'
    'connect'

    # model operations
    'post'
    'list'
    'getOne'
    'delOne'
    'putOne'
    'getMany'
    'delMany'
    'postMany'
    'getManyBackwards'
  ]


promise = (api) ->

  obj = {}
  queue = []
  running = false
  methods = ['connect', 'post', 'list', 'getOne', 'delOne', 'putOne', 'getMany', 'delMany', 'postMany', 'getBackBackwards']

  invoke = (method, args, cb) ->
    method args..., ->
      cb.apply(this, arguments)
      running = false
      pop()

  pop = ->
    return if queue.length == 0

    running = true
    top = queue[0]
    queue = queue.slice(1)

    if top.name?
      top.callback.call (args..., cb) ->
        invoke api[top.name], args, cb
        obj
    else if top.method?
      invoke api[top.method], top.args, top.callback
    else
      top.callback()

  methods.forEach (method) ->
    obj[method] = (args..., callback) ->
      queue.push({ method: method, args: args, callback: callback })
      pop() if !running
      obj

  obj.then = (name, callback) ->
    if !callback?
      callback = name
      name = null

    queue.push({ name: name, callback: callback })
    pop() if !running
    obj

  obj



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



it "should allow model definitions in bulk", ->
  api = manikin.create()

  api.defModels
    surveys:
      owners: {}
      fields: {}
    questions:
      owners:
        survey: 'surveys'
      fields: {}

  api.getModels().should.eql ['surveys', 'questions']




it "should provide an interface for meta data", ->
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

  api.defModel 'customers'
    fields:
      name: { type: 'string' }
      at: { type: 'hasMany', model: 'companies' }


  meta = [
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

  api.getMeta('companies').should.eql
    owners: [{ plur: 'accounts', sing: 'account' }]
    owns: []
    fields: meta
    manyToMany: []

  api.getMeta('accounts').should.eql
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

  api.getMeta('customers').should.eql
    owners: []
    owns: []
    fields: [
      { name: 'at',   readonly: false, required: false, type: 'unknown' }
      { name: 'id',   readonly: true,  required: false, type: 'string'  }
      { name: 'name', readonly: false, required: false, type: 'string'  }
    ]
    manyToMany: [{ ref: 'companies', name: 'at' }]



describe 'Manikin', ->

  beforeEach (done) ->
    mongojs.connect('mongodb://localhost/manikin-test').dropDatabase done


  it "should allow mixed properties in models definitions", (done) ->
    api = manikin.create()

    api.defModel 'stuffs',
      owners: {}
      fields:
        name: { type: 'string' }
        stats: { type: 'mixed' }

    api.connect 'mongodb://localhost/manikin-test', (err) ->
      should.not.exist err
      api.post 'stuffs', { name: 'a1', stats: { s1: 's1', s2: 2 } }, (err, survey) ->
        should.not.exist err
        survey.should.have.keys ['id', 'name', 'stats']
        survey.stats.should.have.keys ['s1', 's2']
        done()



  it "should provide some typical http-operations", (done) ->
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

    api.defModel 'customers'
      fields:
        name: { type: 'string' }
        at: { type: 'hasMany', model: 'companies' }

    saved = {}

    promise(api).connect 'mongodb://localhost/manikin-test', (err) ->
      should.not.exist err
    .post 'accounts', { name: 'n1' }, (err, a1) ->
      should.not.exist err
      a1.should.have.keys ['name', 'id']
      saved.a1 = a1
    .then 'post', -> @ 'accounts', { name: 'n2' }, (err, a2) ->
      should.not.exist err
      a2.should.have.keys ['name', 'id']
      saved.a2 = a2
    .list 'accounts', (err, accs) ->
      should.not.exist err
      accs.should.eql [saved.a1, saved.a2]
    .then 'getOne', -> @ 'accounts', { id: saved.a1.id }, (err, acc) ->
      should.not.exist err
      acc.should.eql saved.a1
    .then 'getOne', -> @ 'accounts', { name: 'n2' }, (err, acc) ->
      should.not.exist err
      acc.should.eql saved.a2
    .then 'getOne', -> @ 'accounts', { name: 'does-not-exist' }, (err, acc) ->
      err.toString().should.eql 'Error: No match'
      should.not.exist acc
    .then done
  





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

    api.connect 'mongodb://localhost/manikin-test', (err) ->
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
