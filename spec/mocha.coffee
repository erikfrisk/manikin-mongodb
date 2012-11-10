manikin = require('./setup').requireSource('manikin')
mongojs = require 'mongojs'
assert = require 'assert'
should = require 'should'
async = require 'async'
_ = require 'underscore'


noErr = (cb) ->
  (err, args...) ->
    should.not.exist err
    cb(args...) if cb


it "should have the right methods", ->
  api = manikin.create()
  api.should.have.keys [
    # definition
    'defModels'

    # meta-methods
    'getModels'
    'getMeta'

    # support-methods
    'isValidId'
    'connect'
    'close'

    # model operations
    'post'
    'list'
    'getOne'
    'delOne'
    'putOne'
    'getMany'
    'delMany'
    'postMany'
  ]


promise = (api) ->

  obj = {}
  queue = []
  running = false
  methods = ['connect', 'close', 'post', 'list', 'getOne', 'delOne', 'putOne', 'getMany', 'delMany', 'postMany']

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

  api.defModels
    surveys:
      owners: {}
      fields: {}
  
    questions:
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



it "should recognize valid object ids", ->
  api = manikin.create()
  api.isValidId('abc').should.eql false



it "should recognize invalid object ids", ->
  api = manikin.create()
  api.isValidId('509cf9b1788d6803a1000004').should.eql true



it "should throw exceptions for invalid types", ->
  api = manikin.create()

  (->
    api.defModels
      some_model:
        fields:
          name: 'an-invalid-type'
  ).should.throw('Invalid type: an-invalid-type')



it "should provide an interface for meta data", ->
  api = manikin.create()

  api.defModels
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
    manyToMany: [{ ref: 'customers', name: 'at', inverseName: 'at' }]

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
      { name: 'id',   readonly: true,  required: false, type: 'string'  }
      { name: 'name', readonly: false, required: false, type: 'string'  }
    ]
    manyToMany: [{ ref: 'companies', name: 'at', inverseName: 'at' }]



describe 'Manikin', ->

  beforeEach (done) ->
    mongojs.connect('mongodb://localhost/manikin-test').dropDatabase done


  it "should allow a basic set of primitive data types to be stored, updated and retrieved", (done) ->
    api = manikin.create()

    api.defModels
      stuffz:
        fields:
          v1: 'string'
          v2: 'number'
          v3: 'date'
          v4: 'boolean'
          v5:
            type: 'nested'
            v6: 'string'
            v7: 'number'

    saved = {}

    promise(api).connect('mongodb://localhost/manikin-test', noErr())
    .post('stuffz', { v1: 'jakob', v2: 12.5, v3: '2012-10-15', v4: true, v5: { v6: 'nest', v7: 7 } }, noErr())
    .list 'stuffz', noErr (list) ->
      saved.id = list[0].id
      list.map((x) -> _(x).omit('id')).should.eql [
        v1: 'jakob'
        v2: 12.5
        v3: '2012-10-15T00:00:00.000Z'
        v4: true
        v5:
          v6: 'nest'
          v7: 7
      ]
    .then 'putOne', -> @ 'stuffz', { v1: 'jakob2', v3: '2012-10-15T13:37:00', v4: false, v5: { v6: 'nest2', v7: 14 } }, { id: saved.id }, noErr (r) ->
      _(r).omit('id').should.eql
        v1: 'jakob2'
        v2: 12.5
        v3: '2012-10-15T13:37:00.000Z'
        v4: false
        v5:
          v6: 'nest2'
          v7: 14
    .then 'getOne', -> @ 'stuffz', { filter: { id: saved.id } }, noErr (r) ->
      _(r).omit('id').should.eql
        v1: 'jakob2'
        v2: 12.5
        v3: '2012-10-15T13:37:00.000Z'
        v4: false
        v5:
          v6: 'nest2'
          v7: 14
    .then ->
      api.close(done)



  it "should detect when an object id does not exist", (done) ->
    api = manikin.create()

    api.defModels
      table:
        fields:
          v1: 'string'

    promise(api).connect('mongodb://localhost/manikin-test', noErr())
    .getOne 'table', { filter: { id: '123' } }, (err, data) ->
      err.should.eql new Error()
      err.toString().should.eql 'Error: No such id'
      should.not.exist data
    .delOne 'table', { id: '123' }, (err, data) ->
      err.should.eql new Error()
      err.toString().should.eql 'Error: No such id'
      should.not.exist data
    .then ->
      api.close(done)



  it "should allow mixed properties in models definitions", (done) ->
    api = manikin.create()

    api.defModels
      stuffs:
        owners: {}
        fields:
          name: { type: 'string' }
          stats: { type: 'mixed' }

    api.connect 'mongodb://localhost/manikin-test', noErr ->
      api.post 'stuffs', { name: 'a1', stats: { s1: 's1', s2: 2 } }, noErr (survey) ->
        survey.should.have.keys ['id', 'name', 'stats']
        survey.stats.should.have.keys ['s1', 's2']
        api.close(done)



  it "should allow default sorting orders", (done) ->
    api = manikin.create()

    api.defModels
      warez:
        owners: {}
        defaultSort: 'name'
        fields:
          name: { type: 'string' }
          stats: { type: 'mixed' }

    promise(api).connect('mongodb://localhost/manikin-test', noErr())
    .post('warez', { name: 'jakob', stats: 1 }, noErr())
    .post('warez', { name: 'erik', stats: 2 }, noErr())
    .post('warez', { name: 'julia', stats: 3 }, noErr())
    .list 'warez', noErr (list) ->
      names = list.map (x) -> x.name
      names.should.eql ['erik', 'jakob', 'julia']
    .then ->
      api.close(done)



  it "should allow simplified field declarations (specifying type only)", (done) ->
    api = manikin.create()

    api.defModels
      leet:
        owners: {}
        fields:
          firstName: 'string'
          lastName: { type: 'string' }
          age: 'number'

    api.connect 'mongodb://localhost/manikin-test', noErr ->
      api.post 'leet', { firstName: 'jakob', lastName: 'mattsson', age: 27 }, noErr (survey) ->
        survey.should.have.keys ['id', 'firstName', 'lastName', 'age']
        survey.should.eql { id: survey.id, firstName: 'jakob', lastName: 'mattsson', age: 27 }
        api.close(done)



  it "should provide some typical http-operations", (done) ->
    api = manikin.create()

    api.defModels
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

      employees:
        owners:
          company: 'companies'
        fields:
          name: { type: 'string', default: '' }

      customers:
        fields:
          name: { type: 'string' }
          at: { type: 'hasMany', model: 'companies' }

    saved = {}

    promise(api).connect('mongodb://localhost/manikin-test', noErr())
    .post 'accounts', { name: 'n1' }, noErr (a1) ->
      a1.should.have.keys ['name', 'id']
      saved.a1 = a1
    .then 'post', -> @ 'accounts', { name: 'n2' }, noErr (a2) ->
      a2.should.have.keys ['name', 'id']
      saved.a2 = a2
    .list 'accounts', noErr (accs) ->
      accs.should.eql [saved.a1, saved.a2]
    .then 'getOne', -> @ 'accounts', { id: saved.a1.id }, noErr (acc) ->
      acc.should.eql saved.a1
    .then 'getOne', -> @ 'accounts', { name: 'n2' }, noErr (acc) ->
      acc.should.eql saved.a2
    .then 'getOne', -> @ 'accounts', { name: 'does-not-exist' }, (err, acc) ->
      err.toString().should.eql 'Error: No match'
      should.not.exist acc

    .then 'post', -> @ 'companies', { account: saved.a1.id, name: 'J Dev AB', orgnr: '556767-2208' }, noErr (company) ->
      company.should.have.keys ['name', 'orgnr', 'account', 'id', 'at']
      saved.c1 = company
    .then 'post', -> @ 'companies', { account: saved.a1.id, name: 'Lean Machine AB', orgnr: '123456-1234' }, noErr (company) ->
      company.should.have.keys ['name', 'orgnr', 'account', 'id', 'at']
      saved.c2 = company
    .then 'post', -> @ 'employees', { company: saved.c1.id, name: 'Jakob' }, noErr (company) ->
      company.should.have.keys ['name', 'company', 'account', 'id']

    # testing to get an account without nesting
    .then 'getOne', -> @ 'accounts', { id: saved.a1.id }, noErr (acc) ->
      _(acc).omit('id').should.eql { name: 'n1' }

    # testing to get an account with nesting
    .then 'getOne', -> @ 'accounts', { nesting: 1, filter: { id: saved.a1.id } }, noErr (acc) ->
      _(acc).omit('id').should.eql { name: 'n1' }


    .then ->
      api.close(done)
  



  it "should be possible to query many-to-many-relationships", (done) ->
    api = manikin.create()

    api.defModels
      people:
        owners: {}
        fields:
          name: { type: 'string', default: '' }
          boundDevices: { type: 'hasMany', model: 'devices', inverseName: 'boundPeople' }

      devices:
        owners: {}
        fields:
          name: { type: 'string', default: '' }

    saved = {}

    promise(api).connect('mongodb://localhost/manikin-test', noErr())
    .post 'people', { name: 'q1' }, noErr (q1) ->
      saved.q1 = q1
    .post 'people', { name: 'q2' }, noErr (q2) ->
      saved.q2 = q2
    .post 'devices', { name: 'd1' }, noErr (d1) ->
      saved.d1 = d1
    .post 'devices', { name: 'd2' }, noErr (d2) ->
      saved.d2 = d2
    .then 'postMany', -> @('people',  saved.q1.id, 'boundDevices', saved.d1.id, noErr())
    .then 'postMany', -> @('people',  saved.q1.id, 'boundDevices', saved.d2.id, noErr())
    .then 'getMany',  -> @('people',  saved.q1.id, 'boundDevices', noErr((data) -> data.length.should.eql 2))
    .then 'getMany',  -> @('people',  saved.q2.id, 'boundDevices', noErr((data) -> data.length.should.eql 0))
    .then 'getMany',  -> @('devices', saved.d1.id, 'boundPeople',  noErr((data) -> data.length.should.eql 1))
    .then 'getMany',  -> @('devices', saved.d2.id, 'boundPeople',  noErr((data) -> data.length.should.eql 1))
    .then 'delMany',  -> @('people',  saved.q1.id, 'boundDevices', saved.d1.id, noErr())

    .then -> api.close(done)



  it "should not be ok to post without specifiying the owner", (done) ->
    api = manikin.create()

    api.defModels
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

    api.connect 'mongodb://localhost/manikin-test', noErr ->
      api.post 'accounts', { name: 'a1' }, noErr (account) ->
        account.should.have.keys ['name', 'id']
        api.post 'companies', { name: 'n', orgnr: 'nbr' }, (err, company) ->
          should.exist err # expect something more precise...
          api.close(done)



  it "should allow custom validators", (done) ->
    api = manikin.create()

    api.defModels
      pizzas:
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

    api.connect 'mongodb://localhost/manikin-test', noErr ->
      async.forEach indata, (d, callback) ->
        api.post 'pizzas', { name: d.name }, (err, res) ->
          if d.response != null
            err.message.should.eql 'Validation failed'
            err.errors.name.path.should.eql 'name'
          callback()
      , ->
        api.close(done)



  it "should introduce redundant references to all ancestors", (done) ->
    api = manikin.create()

    api.defModels
      accounts:
        owners: {}
        fields:
          name: { type: 'string', default: '' }

      companies2:
        owners:
          account: 'accounts'
        fields:
          name: { type: 'string', default: '' }
          orgnr: { type: 'string', default: '' }

      contacts:
        owners:
          company: 'companies2'
        fields:
          email: { type: 'string', default: '' }
          phone: { type: 'string', default: '' }

      pets:
        owners:
          contact: 'contacts'
        fields:
          race: { type: 'string', default: '' }

    api.connect 'mongodb://localhost/manikin-test', noErr ->
      api.post 'accounts', { name: 'a1', bullshit: 123 }, noErr (account) ->
        account.should.have.keys ['name', 'id']
        api.post 'companies2', { name: 'n', orgnr: 'nbr', account: account.id }, noErr (company) ->
          company.should.have.keys ['id', 'name', 'orgnr', 'account']
          api.post 'contacts', { email: '@', phone: '112', company: company.id }, noErr (contact) ->
            contact.should.have.keys ['id', 'email', 'phone', 'account', 'company']
            api.post 'pets', { race: 'dog', contact: contact.id }, noErr (pet) ->
              pet.should.have.keys ['id', 'race', 'account', 'company', 'contact']
              api.close(done)
