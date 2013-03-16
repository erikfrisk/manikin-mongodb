assert = require 'assert'
should = require 'should'
async = require 'async'
_ = require 'underscore'

noErr = (cb) ->
  (err, args...) ->
    should.not.exist err
    cb(args...) if cb

exports.runTests = (manikin, dropDatabase, connectionData) ->

  it "should have the right methods", ->
    manikin.should.have.keys [
      'create'
    ]

    api = manikin.create()
    api.should.have.keys [
      # support-methods
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



  describe 'Manikin', ->

    beforeEach (done) ->
      dropDatabase(connectionData, done)

    after (done) ->
      dropDatabase(connectionData, done)



    it "should be able to connect even if no models have been defined", (done) ->
      api = manikin.create()
      promise(api).connect connectionData, {}, noErr ->
        api.close(done)



    it "should raise an error if an invalid connection string is given", (done) ->
      api = manikin.create()
      api.connect "invalid-connection-string", {}, (err) ->
        err.should.eql new Error()
        err.toString().should.match /^Error:/
        done()



    describe 'should not save configuration between test runs', ->
      commonModelName = 'stuffzz'

      it "stores things for the first test run", (done) ->
        api = manikin.create()
        model = _.object([[commonModelName,
          fields:
            v1: 'string'
        ]])
        promise(api).connect(connectionData, model, noErr())
        .post(commonModelName, { v2: '1', v1: '2' }, noErr())
        .list commonModelName, {}, noErr (list) ->
          list.length.should.eql 1
          list[0].should.have.keys ['v1', 'id']
          list[0].v1.should.eql '2'
          api.close(done)

      it "stores different things for the second test run", (done) ->
        api = manikin.create()
        model = _.object([[commonModelName,
          fields:
            v2: 'string'
        ]])
        promise(api).connect(connectionData, model, noErr())
        .post(commonModelName, { v2: '3', v1: '4' }, noErr())
        .list commonModelName, {}, noErr (list) ->
          list.length.should.eql 1
          list[0].should.have.keys ['v2', 'id']
          list[0].v2.should.eql '3'
          api.close(done)



    it "should allow a basic set of primitive data types to be stored, updated and retrieved", (done) ->
      api = manikin.create()

      model =
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

      promise(api).connect(connectionData, model, noErr())
      .post('stuffz', { v1: 'jakob', v2: 12.5, v3: '2012-10-15', v4: true, v5: { v6: 'nest', v7: 7 } }, noErr())
      .list 'stuffz', {}, noErr (list) ->
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

      model =
        table:
          fields:
            v1: 'string'

      promise(api).connect(connectionData, model, noErr())
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

      model =
        stuffs:
          owners: {}
          fields:
            name: { type: 'string' }
            stats: { type: 'mixed' }

      api.connect connectionData, model, noErr ->
        api.post 'stuffs', { name: 'a1', stats: { s1: 's1', s2: 2 } }, noErr (survey) ->
          survey.should.have.keys ['id', 'name', 'stats']
          survey.stats.should.have.keys ['s1', 's2']
          api.close(done)



    it "should allow default sorting orders", (done) ->
      api = manikin.create()

      model =
        warez:
          owners: {}
          defaultSort: 'name'
          fields:
            name: { type: 'string' }
            stats: { type: 'mixed' }

      promise(api).connect(connectionData, model, noErr())
      .post('warez', { name: 'jakob', stats: 1 }, noErr())
      .post('warez', { name: 'erik', stats: 2 }, noErr())
      .post('warez', { name: 'julia', stats: 3 }, noErr())
      .list 'warez', {}, noErr (list) ->
        names = list.map (x) -> x.name
        names.should.eql ['erik', 'jakob', 'julia']
      .then ->
        api.close(done)



    it "should allow simplified field declarations (specifying type only)", (done) ->
      api = manikin.create()

      model =
        leet:
          owners: {}
          fields:
            firstName: 'string'
            lastName: { type: 'string' }
            age: 'number'

      api.connect connectionData, model, noErr ->
        api.post 'leet', { firstName: 'jakob', lastName: 'mattsson', age: 27 }, noErr (survey) ->
          survey.should.have.keys ['id', 'firstName', 'lastName', 'age']
          survey.should.eql { id: survey.id, firstName: 'jakob', lastName: 'mattsson', age: 27 }
          api.close(done)



    it "should provide some typical http-operations", (done) ->
      api = manikin.create()

      model =
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

      promise(api).connect(connectionData, model, noErr())
      .post 'accounts', { name: 'n1' }, noErr (a1) ->
        a1.should.have.keys ['name', 'id']
        saved.a1 = a1
      .then 'post', -> @ 'accounts', { name: 'n2' }, noErr (a2) ->
        a2.should.have.keys ['name', 'id']
        saved.a2 = a2
      .list 'accounts', {}, noErr (accs) ->
        accs.should.eql [saved.a1, saved.a2]
      .then 'getOne', -> @ 'accounts', { filter: { id: saved.a1.id } }, noErr (acc) ->
        acc.should.eql saved.a1
      .then 'getOne', -> @ 'accounts', { filter: { name: 'n2' } }, noErr (acc) ->
        acc.should.eql saved.a2
      .then 'getOne', -> @ 'accounts', { filter: { name: 'does-not-exist' } }, (err, acc) ->
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
      .then 'getOne', -> @ 'accounts', { filter: { id: saved.a1.id } }, noErr (acc) ->
        _(acc).omit('id').should.eql { name: 'n1' }

      # testing to get an account with nesting
      .then 'getOne', -> @ 'accounts', { nesting: 1, filter: { id: saved.a1.id } }, noErr (acc) ->
        _(acc).omit('id').should.eql { name: 'n1' }


      .then ->
        api.close(done)




    it "should delete many-to-many-relations when objects are deleted", (done) ->
      api = manikin.create()

      model =
        petsY:
          fields:
            name: 'string'

        foodsY:
          fields:
            name: 'string'
            eatenBy: { type: 'hasMany', model: 'petsY', inverseName: 'eats' }

      saved = {}

      promise(api).connect(connectionData, model, noErr())
      .then 'post', -> @('petsY', { name: 'pet1' }, noErr (res) -> saved.pet1 = res)
      .then 'post', -> @('foodsY', { name: 'food1' }, noErr (res) -> saved.food1 = res)
      .then 'postMany', -> @('foodsY', saved.food1.id, 'eatenBy', saved.pet1.id, noErr())
      .then 'getMany', -> @('petsY', saved.pet1.id, 'eats', noErr((data) -> data.length.should.eql 1))
      .then 'delOne', -> @('petsY', { id: saved.pet1.id }, noErr())
      .then 'list', -> @('petsY', { }, noErr((data) -> data.length.should.eql 0))
      .then 'list', -> @('foodsY', { }, noErr (data) -> data.should.eql [
        id: saved.food1.id
        name: 'food1'
        eatenBy: []
      ])
      .then -> api.close(done)



    it "should be possible to query many-to-many-relationships", (done) ->
      api = manikin.create()

      model =
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

      promise(api).connect(connectionData, model, noErr())
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
      .then 'getMany',  -> @('people',  saved.q1.id, 'boundDevices', noErr((data) -> data.length.should.eql 1))
      .then 'getMany',  -> @('people',  saved.q2.id, 'boundDevices', noErr((data) -> data.length.should.eql 0))
      .then 'getMany',  -> @('devices', saved.d1.id, 'boundPeople',  noErr((data) -> data.length.should.eql 0))
      .then 'getMany',  -> @('devices', saved.d2.id, 'boundPeople',  noErr((data) -> data.length.should.eql 1))

      .then -> api.close(done)




    it "should delete many-to-many-relations even when owners of the related objects are deleted", (done) ->
      api = manikin.create()

      model =
        peopleX:
          fields:
            name: 'string'

        petsX:
          owners: { person: 'peopleX' }
          fields:
            name: 'string'

        foodsX:
          owners: {}
          fields:
            name: 'string'
            eatenBy: { type: 'hasMany', model: 'petsX', inverseName: 'eats' }

      saved = {}

      promise(api).connect(connectionData, model, noErr())
      .post 'peopleX', { name: 'p1' }, noErr (res) ->
        saved.person = res
      .then 'post', -> @('petsX', { person: saved.person.id, name: 'pet1' }, noErr (res) -> saved.pet1 = res)
      .then 'post', -> @('foodsX', { name: 'food1' }, noErr (res) -> saved.food1 = res)
      .then 'postMany', -> @('foodsX',  saved.food1.id, 'eatenBy', saved.pet1.id, noErr())
      .then 'getMany',  -> @('petsX', saved.pet1.id, 'eats', noErr((data) -> data.length.should.eql 1))
      .then 'delOne',  -> @('peopleX', { id: saved.person.id }, noErr())
      .then 'list',  -> @('peopleX', { }, noErr((data) -> data.length.should.eql 0))
      .then 'list',  -> @('petsX', { }, noErr((data) -> data.length.should.eql 0))
      .then 'list',  -> @('foodsX', { }, noErr (data) -> data.should.eql [
        id: saved.food1.id
        name: 'food1'
        eatenBy: []
      ])
      .then -> api.close(done)



    it "should prevent duplicate many-to-many values, even when data is posted in parallel", (done) ->
      api = manikin.create()

      model =
        typeA:
          fields:
            name: 'string'

        typeB:
          fields:
            name: 'string'
            belongsTo: { type: 'hasMany', model: 'typeA', inverseName: 'belongsTo2' }

      saved = {}
      resultStatuses = {}

      api.connect connectionData, model, noErr ->
        api.post 'typeA', { name: 'a1' }, noErr (a1) ->
          api.post 'typeB', { name: 'b1' }, noErr (b1) ->
            async.forEach [1,2,3], (item, callback) ->
              api.postMany 'typeB', b1.id, 'belongsTo', a1.id, noErr (result) ->
                resultStatuses[result.status] = resultStatuses[result.status] || 0
                resultStatuses[result.status]++
                callback()
            , ->
              resultStatuses['inserted'].should.eql 1
              resultStatuses['insert already in progress'].should.eql 2
              api.list 'typeA', {}, noErr (x) ->
                x[0].belongsTo2.length.should.eql 1
                api.close(done)



    it "should prevent duplicate many-to-many values, even when data is posted in parallel, to both end-points", (done) ->
      api = manikin.create()

      model =
        typeC:
          fields:
            name: 'string'

        typeD:
          fields:
            name: 'string'
            belongsTo: { type: 'hasMany', model: 'typeC', inverseName: 'belongsTo2' }

      saved = {}
      resultStatuses = {}

      api.connect connectionData, model, noErr ->
        api.post 'typeC', { name: 'c1' }, noErr (c1) ->
          api.post 'typeD', { name: 'd1' }, noErr (d1) ->
            async.forEach [['typeC', c1.id, 'belongsTo2', d1.id], ['typeD', d1.id, 'belongsTo', c1.id]], (item, callback) ->
              f = noErr (result) ->
                resultStatuses[result.status] = resultStatuses[result.status] || 0
                resultStatuses[result.status]++
                callback()
              api.postMany.apply(api, item.concat([f]))
            , ->
              resultStatuses['inserted'].should.eql 1
              resultStatuses['insert already in progress'].should.eql 1
              api.list 'typeC', {}, noErr (x) ->
                x[0].belongsTo2.length.should.eql 1
                api.close(done)



    it "should raise an error on posts to invalid many to many-properties", (done) ->
      api = manikin.create()

      model =
        typeA:
          fields:
            name: 'string'

        typeB:
          fields:
            name: 'string'
            belongsTo: { type: 'hasMany', model: 'typeA' }

      saved = {}
      api.connect connectionData, model, noErr ->
        api.post 'typeA', { name: 'a' }, noErr (a) ->
          api.post 'typeB', { name: 'b' }, noErr (b) ->
            api.postMany 'typeA', a.id, 'relation-that-does-not-exist', b.id, (err) ->
              err.should.eql new Error()
              err.toString().should.eql 'Error: Invalid many-to-many property'
              api.close(done)



    it "should raise an error on deletes to invalid many to many-properties", (done) ->
      api = manikin.create()

      model =
        typeA:
          fields:
            name: 'string'

        typeB:
          fields:
            name: 'string'
            belongsTo: { type: 'hasMany', model: 'typeA' }

      saved = {}
      api.connect connectionData, model, noErr ->
        api.post 'typeA', { name: 'a' }, noErr (a) ->
          api.post 'typeB', { name: 'b' }, noErr (b) ->
            api.delMany 'typeA', a.id, 'relation-that-does-not-exist', b.id, (err) ->
              err.should.eql new Error()
              err.toString().should.eql 'Error: Invalid many-to-many property'
              api.close(done)



    it "should not be ok to post without specifiying the owner", (done) ->
      api = manikin.create()

      model =
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

      api.connect connectionData, model, noErr ->
        api.post 'accounts', { name: 'a1' }, noErr (account) ->
          account.should.have.keys ['name', 'id']
          api.post 'companies', { name: 'n', orgnr: 'nbr' }, (err, company) ->
            should.exist err # expect something more precise...
            api.close(done)



    it "should raise an error if a putOne attempts to put non-existing fields", (done) ->
      api = manikin.create()

      model =
        accounts:
          fields:
            name: { type: 'string', default: '' }

      api.connect connectionData, model, noErr ->
        api.post 'accounts', { name: 'a1' }, noErr (account) ->
          api.putOne 'accounts', { name: 'n1', age: 10, desc: 'test' }, { id: account.id }, (err, data) ->
            err.should.eql new Error()
            err.toString().should.eql 'Error: Invalid fields: age, desc'
            api.close(done)



    it "should raise an error if a putOne attempts to put using an id from another collection", (done) ->
      api = manikin.create()

      model =
        accounts:
          fields:
            name: { type: 'string', default: '' }
        other:
          fields:
            name: { type: 'string', default: '' }

      api.connect connectionData, model, noErr ->
        api.post 'other', { name: 'a1' }, noErr (other) ->
          api.post 'accounts', { name: 'a1' }, noErr (account) ->
            api.putOne 'accounts', { name: 'n1' }, { id: other.id }, (err, data) ->
              err.should.eql new Error()
              err.toString().should.eql 'Error: No such id'
              api.close(done)



    it "should raise an error if a putOne attempts to put using an id from another collection", (done) ->
      api = manikin.create()

      model =
        accounts:
          fields:
            name: { type: 'string', default: '' }

      api.connect connectionData, model, noErr ->
        api.post 'accounts', { name: 'a1' }, noErr (account) ->
          api.putOne 'accounts', { name: 'n1' }, { id: 1 }, (err, data) ->
            err.should.eql new Error()
            err.toString().should.eql 'Error: No such id'
            api.close(done)



    it "should allow custom validators", (done) ->
      api = manikin.create()

      model =
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

      api.connect connectionData, model, noErr ->
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

      model =
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

      saved = {}

      promise(api).connect(connectionData, model, noErr())
      .post 'accounts', { name: 'a1', bullshit: 123 }, noErr (account) ->
        account.should.have.keys ['name', 'id']
        saved.account = account
      .then 'post', -> @ 'companies2', { name: 'n', orgnr: 'nbr', account: saved.account.id }, noErr (company) ->
        saved.company = company
        company.should.have.keys ['id', 'name', 'orgnr', 'account']
      .then 'post', -> @ 'companies2', { name: 'n2', orgnr: 'nbr', account: saved.account.id }, noErr (company2) ->
        saved.company2 = company2
        company2.should.have.keys ['id', 'name', 'orgnr', 'account']
      .then 'post', -> @ 'contacts', { email: '@', phone: '112', company: saved.company.id }, noErr (contact) ->
        saved.contact = contact
        contact.should.have.keys ['id', 'email', 'phone', 'account', 'company']
      .then 'post', -> @ 'contacts', { email: '@2', phone: '911', company: saved.company2.id }, noErr (contact2) ->
        saved.contact2 = contact2
        contact2.should.have.keys ['id', 'email', 'phone', 'account', 'company']
      .then 'post', -> @ 'pets', { race: 'dog', contact: saved.contact.id }, noErr (pet) ->
        pet.should.have.keys ['id', 'race', 'account', 'company', 'contact']
        pet.contact.should.eql saved.contact.id
        pet.company.should.eql saved.company.id
        pet.account.should.eql saved.account.id
      .then 'post', -> @ 'pets', { race: 'dog', contact: saved.contact2.id }, noErr (pet) ->
        pet.should.have.keys ['id', 'race', 'account', 'company', 'contact']
        pet.contact.should.eql saved.contact2.id
        pet.company.should.eql saved.company2.id
        pet.account.should.eql saved.account.id

      .list('pets', {}, noErr ((res) -> res.length.should.eql 2))
      .list('contacts', {}, noErr ((res) -> res.length.should.eql 2))
      .list('companies2', {}, noErr ((res) -> res.length.should.eql 2))
      .list('accounts', {}, noErr ((res) -> res.length.should.eql 1))

      .then('delOne', -> @ 'companies2', { id: saved.company.id }, noErr())

      .list('pets', {}, noErr ((res) -> res.length.should.eql 1))
      .list('contacts', {}, noErr ((res) -> res.length.should.eql 1))
      .list('companies2', {}, noErr ((res) -> res.length.should.eql 1))
      .list('accounts', {}, noErr ((res) -> res.length.should.eql 1))

      .then -> api.close(done)


    it "should provide has-one-relations", (done) ->
      api = manikin.create()
      model =

        accounts:
          defaultSort: 'name'
          fields:
            email: 'string'

        questions:
          owners: account: 'accounts'
          defaultSort: 'order'
          fields:
            text: 'string'

        devices:
          owners: account: 'accounts'
          fields:
            name: 'string'

        answers:
          owners: question: 'questions'
          fields:
            option: 'number'
            device:
              type: 'hasOne'
              model: 'devices'

      saved = {}
      promise(api).connect(connectionData, model, noErr())
      .post 'accounts', { email: 'some@email.com' }, noErr (account) ->
        saved.account = account
      .then 'post', -> @ 'questions', { name: 'q1', account: saved.account.id }, noErr (question) ->
        saved.q1 = question
      .then 'post', -> @ 'questions', { name: 'q2', account: saved.account.id }, noErr (question) ->
        saved.q2 = question
      .then 'post', -> @ 'devices', { name: 'd1', account: saved.account.id }, noErr (device) ->
        saved.d1 = device
      .then 'post', -> @ 'devices', { name: 'd1', account: saved.account.id }, noErr (device) ->
        saved.d2 = device

      # Can set it to a deviceID
      .then 'post', -> @ 'answers', { option: 1, question: saved.q1.id, device: saved.d1.id }, noErr (answer) ->
        answer.device.should.eql saved.d1.id
        saved.a1 = answer

      #Can set it to null
      .then 'post', -> @ 'answers', { option: 1, question: saved.q1.id, device: null }, noErr (answer) ->
        should.not.exist answer.device
        saved.a2 = answer

      # Can update it to null
      .then 'putOne', -> @ 'answers', { device: null }, { id: saved.a1.id }, noErr (answer) ->
        should.not.exist answer.device

      # Can update it to another device
      .then 'putOne', -> @ 'answers', { device: saved.d2.id }, { id: saved.a1.id }, noErr (answer) ->
        answer.device.should.eql saved.d2.id

      # If the devices is deleted, the answers device is set to null
      .then 'delOne', -> @ 'devices', { id: saved.d2.id }, noErr () ->
        (1).should.eql 1
      .then 'getOne', -> @ 'answers', { filter: { id: saved.a1.id } }, noErr (answer) ->
        should.not.exist answer.device

      # Can't update it to something that is not a key of the correct type
      .then 'putOne', -> @ 'answers', { device: saved.a2.id }, { id: saved.a1.id }, (err, answer) ->
        err.should.eql new Error()
        err.toString().should.eql "Error: Invalid hasOne-key for 'device'"
        should.not.exist answer

      .then(done)


    it "should be possible to add objects even when their hasOnes-collections are empty", (done) ->
      api = manikin.create()
      model =
        bananas:
          owners: {}
          fields:
            color: 'string'

        monkeys:
          owners: {}
          fields:
            name: 'string'
            banana:
              type: 'hasOne'
              model: 'bananas'

      saved = {}
      promise(api).connect(connectionData, model, noErr())
      .then 'post', -> @ 'monkeys', { name: 'george' }, noErr (monkey) ->
        saved.monkey = monkey
      .then 'list', -> @ 'monkeys', {}, noErr (monkeys) ->
        monkeys.length.should.eql 1
      .then(done)
