"use strict"

async = require 'async'
_ = require 'underscore'


desugar = (superspec) -> superspec
getMeta = (desugaredSpec) -> desugaredSpec



getAllOwners = (specmodels, modelName) ->
  owners = specmodels[modelName].owners
  indirect = _.values(owners).map (model) -> getAllOwners(specmodels, model)
  _.extend {}, owners, indirect...

getAllIndirectOwners = (specmodels, modelName) ->
  owners = specmodels[modelName].owners
  indirect = _.flatten _.values(owners).map (model) -> getAllOwners(specmodels, model)
  _.extend {}, indirect...



desugarModel = (modelName, tgt, src, keys) ->
  keys.forEach (key) ->
    if typeof src[key] == 'string'
      obj = {}
      obj[key] = { type: src[key] }
      desugarModel(modelName, tgt, obj, [key])
    else if !src[key].type?
      throw new Error("must assign a type: " + key)
    else if src[key].type == 'mixed'
      tgt[key] = { type: 'mixed' }
    else if src[key].type == 'nested'
      tgt[key] = { type: 'nested' }
      desugarModel(modelName, tgt[key], src[key], _.without(Object.keys(src[key]), 'type'))
    else if _(['string', 'number', 'date', 'boolean']).contains(src[key].type)
      tgt[key] =
        type: src[key].type
        required: !!src[key].required
        index: !!src[key].index
        unique: !!src[key].unique
      tgt[key].default = src[key].default if src[key].default?
      tgt[key].validate = src[key].validate if src[key].validate?
    else if src[key].type == 'hasOne'
      tgt[key] = src[key]
    else if src[key].type == 'hasMany'
      tgt[key] = src[key]
      tgt[key].inverseName = src[key].inverseName || key
    else
      throw new Error("Invalid type: " + src[key].type)


preprocFilter = (filter) ->
  x = _.extend({}, filter)
  x._id = x.id if x.id
  delete x.id
  x


massageOne = (x) ->
  return x if !x?
  x.id = x._id
  delete x._id
  x


massageCore = (r2) -> if Array.isArray r2 then r2.map massageOne else massageOne r2

massage = (r2) -> massageCore(JSON.parse(JSON.stringify(r2)))


massaged = (f) -> (err, data) ->
  if err
    f(err)
  else
    f(null, massage(data))



propagate = (callback, f) ->
  (err, args...) ->
    if err
      callback(err)
    else
      f.apply(this, args)


getKeys = (data, target = [], prefix = '') ->
  valids = ['Array', 'String', 'Boolean', 'Date', 'Number', 'Null']

  Object.keys(data).forEach (key) ->
    if valids.some((x) -> _(data[key])['is' + x]())
      target.push(prefix + key)
    else
      getKeys(data[key], target, prefix + key + '.')

  target





















exports.create = ->

  # Silly hack to make this project testable without caching gotchas
  if process.env.NODE_ENV != 'production'
    for key of require.cache
      delete require.cache[key]
  mongoose = require 'mongoose'


  # Shorthands for some moongoose types
  Schema = mongoose.Schema
  Mixed = mongoose.Schema.Types.Mixed
  ObjectID = mongoose.mongo.ObjectID  # Yes, they seriously have two different objects with
  ObjectId = mongoose.Schema.ObjectId # the same name but with different casings. Idiots...

  db = null
  connection = null
  api = {}
  models = {}
  specmodels = {}
  meta = {}

  makeModel = (name, schema) ->
    ss = new Schema schema,
      strict: true
    ss.set('versionKey', false)
    connection.model name, ss, name

  api.isValidId = (id) ->
    try
      ObjectID(id)
      true
    catch ex
      false






  # Connecting to db
  # ================
  api.connect = (databaseUrl, callback) ->
    connection = mongoose.createConnection databaseUrl

    toDef.forEach ([name, v]) ->
      models[name] = makeModel name, v.fields
      models[name].schema.pre 'save', nullablesValidation(models[name].schema)
      models[name].schema.pre 'remove', (next) -> preRemoveCascadeNonNullable(models[name], this._id.toString(), next)
      models[name].schema.pre 'remove', (next) -> preRemoveCascadeNullable(models[name], this._id.toString(), next)

    callback()


  api.close = (callback) ->
    connection.close()
    callback()


  # The five base methods
  # =====================
  api.list = (model, filter, callback) ->
    filter = preprocFilter(filter)

    rr = models[model].find(filter)
    if meta[model].defaultSort?
      rr = rr.sort _.object [[meta[model].defaultSort, 'asc']]
    rr.exec(massaged(callback))

  api.getOne = (model, config, callback) ->
    filter = preprocFilter(config.filter || {})

    models[model].findOne filter, (err, data) ->
      if err
        if err.toString() == 'Error: Invalid ObjectId'
          callback(new Error('No such id'))
        else
          callback(err)
        return
      else if !data?
        callback(new Error('No match'))
      else
        callback null, massage(data)

  api.delOne = (model, filter, callback) ->
    filter = preprocFilter(filter)

    models[model].findOne filter, (err, d) ->
      if err
        if err.toString() == 'Error: Invalid ObjectId'
          callback(new Error('No such id'))
        else
          callback(err)
      else if !d?
        callback(new Error('No such id'))
      else
        d.remove (err) ->
          callback err, if !err then massage(d)



  api.putOne = (modelName, data, filter, callback) ->
    filter = preprocFilter(filter)

    model = models[modelName]
    inputFieldsValid = getKeys data
    inputFields = Object.keys data
    validField = Object.keys(model.schema.paths)

    invalidFields = _.difference(inputFieldsValid, validField)

    if invalidFields.length > 0
      callback(new Error("Invalid fields: " + invalidFields.join(', ')))
      return

    model.findOne filter, propagate callback, (d) ->
      if !d?
        callback(new Error("No such id"))
        return

      inputFields.forEach (key) ->
        d[key] = data[key]

      d.save (err) ->
        callback(err, if err then null else massage(d))




  # Sub-methods
  # ===========
  api.post = (model, indata, callback) ->

    saveFunc = (data) ->
      new models[model](data).save (err) ->
        if err && err.code == 11000
          fieldMatch = err.err.match(/\$([a-zA-Z]+)_1/)
          valueMatch = err.err.match(/"([a-zA-Z]+)"/)
          if fieldMatch && valueMatch
            callback(new Error("Duplicate value '#{valueMatch[1]}' for #{fieldMatch[1]}"))
          else
            callback(new Error("Unique constraint violated"))
        else
          massaged(callback).apply(this, arguments)


    getOwners = (m) -> api.getMeta(m).owners

    ownersRaw = getOwners(model)
    owners = _(ownersRaw).pluck('plur')
    ownersOwners = _(owners.map (x) -> getOwners(x)).flatten()

    if ownersOwners.length == 0
      saveFunc indata
    else
      # Should get all the owners and not just the first.
      # At the moment Im only working with single owners though, so it's for for now...
      api.getOne owners[0], { filter: { id: indata[ownersRaw[0].sing] } }, (err, ownerdata) ->
        paths = models[owners[0]].schema.paths
        metaFields = Object.keys(paths).filter (key) -> !!paths[key].options['x-owner'] || !!paths[key].options['x-indirect-owner']
        metaFields.forEach (key) ->
          indata[key] = ownerdata[key]
        saveFunc indata

  internalListSub = (model, outer, id, filter, callback) ->
    if !callback?
      callback = filter
      filter = {}

    if filter[outer]? && filter[outer].toString() != id.toString()
      callback(new Error('No such id'))
      return

    filter = preprocFilter(filter)
    finalFilter = _.extend({}, filter, _.object([[outer, id]]))

    models[model].find finalFilter, callback




  # The many-to-many methods
  # ========================
  api.delMany = (primaryModel, primaryId, propertyName, secondaryId, callback) ->

    mm = api.getMeta(primaryModel).manyToMany.filter((x) -> x.name == propertyName)[0]

    if mm == null
      callback(new Error('Invalid manyToMany-property'))
      return

    secondaryModel = mm.ref
    inverseName = mm.inverseName

    async.forEach [
      model: primaryModel
      id: primaryId
      property: propertyName
      secondaryId: secondaryId
    ,
      model: secondaryModel
      id: secondaryId
      property: inverseName
      secondaryId: primaryId
    ], (item, callback) ->

      models[item.model].findById item.id, propagate callback, (data) ->
        conditions = { _id: item.id }
        update = { $pull: _.object([[item.property, item.secondaryId]]) }
        options = { }
        models[item.model].update conditions, update, options, (err, numAffected) ->
          callback(err)

    , callback


  insertOps = []

  api.postMany = (primaryModel, primaryId, propertyName, secondaryId, callback) ->

    mm = api.getMeta(primaryModel).manyToMany.filter((x) -> x.name == propertyName)[0]

    if mm == null
      callback(new Error('Invalid manyToMany-property'))
      return

    secondaryModel = mm.ref
    inverseName = mm.inverseName

    insertOpNow = [
      { primaryModel: primaryModel, primaryId: primaryId, propertyName: propertyName, secondaryId: secondaryId }
      { primaryModel: secondaryModel, primaryId: secondaryId, propertyName: inverseName, secondaryId: primaryId }
    ]

    insertOpMatch = (x1, x2) ->
      x1.primaryModel == x2.primaryModel &&
      x1.primaryId    == x2.primaryId    &&
      x1.propertyName == x2.propertyName &&
      x1.secondaryId  == x2.secondaryId

    hasAlready = insertOps.some((x) -> insertOpNow.some((y) -> insertOpMatch(x, y)))

    if hasAlready
      callback(null, { status: 'insert already in progress' })
      return

    insertOpNow.forEach (op) ->
      insertOps.push(op)

    async.map insertOpNow, (item, callback) ->
      models[item.primaryModel].findById item.primaryId, callback
    , propagate callback, (datas) ->

      updated = [false, false]

      insertOpNow.forEach (conf, i) ->
        if -1 == datas[i][conf.propertyName].indexOf conf.secondaryId
          datas[i][conf.propertyName].push conf.secondaryId
          updated[i] = true

      async.forEach [0, 1], (index, callback) ->
        if updated[index]
          datas[index].save(callback)
        else
          callback()
      , (err) ->

        insertOps = insertOps.filter (x) -> !_(insertOpNow).contains(x)

        # how to handle if one of these manages to save, but not the other?
        # the database will end up in an invalid state! is it possible to do some kind of transaction?
        # simulate such a failure and solve it using two phase commits: http://docs.mongodb.org/manual/tutorial/perform-two-phase-commits

        callback(err, { status: (if updated.some((x) -> x) then 'inserted' else 'already inserted') })


  api.getMany = (primaryModel, primaryId, propertyName, callback) ->
    models[primaryModel]
    .findOne({ _id: primaryId })
    .populate(propertyName)
    .exec (err, story) ->
      callback err, massage(story[propertyName])









  specTransform = (allspec, modelName, tgt, src, keys) ->
    keys.forEach (key) ->
      if src[key].type == 'mixed'
        tgt[key] = { type: Mixed }
      else if src[key].type == 'nested'
        tgt[key] = {}
        specTransform(allspec, modelName, tgt[key], src[key], _.without(Object.keys(src[key]), 'type'))
      else if src[key].type == 'string'
        tgt[key] = _.extend({}, src[key], { type: String })

        if src[key].validate?
          tgt[key].validate = (value, callback) ->
            src[key].validate(api, value, callback)

      else if src[key].type == 'number'
        tgt[key] = _.extend({}, src[key], { type: Number })
      else if src[key].type == 'date'
        tgt[key] = _.extend({}, src[key], { type: Date })
      else if src[key].type == 'boolean'
        tgt[key] = _.extend({}, src[key], { type: Boolean })
      else if src[key].type == 'hasOne'
        tgt[key] = { ref: src[key].model, 'x-validation': src[key].validation }
      else if src[key].type == 'hasMany'
        tgt[key] = [{ type: ObjectId, ref: src[key].model, inverseName: src[key].inverseName }]
        allspec[src[key].model][src[key].inverseName] = [{ type: ObjectId, ref: modelName, inverseName: key }]

  api.defModels = (models) ->

    rest = {}

    Object.keys(models).forEach (modelName) ->
      spec = {}
      inspec = models[modelName].fields || {}
      desugarModel(modelName, spec, inspec, Object.keys(inspec))
      rest[modelName] = _.extend({}, models[modelName], { fields: spec })
      if !rest[modelName].owners
        rest[modelName].owners = {}

    specmodels = rest

    newrest = {}

    allspec = {}
    Object.keys(rest).forEach (modelName) ->
      allspec[modelName] = {}

    Object.keys(rest).forEach (modelName) ->
      spec = allspec[modelName]
      owners = rest[modelName].owners || {}
      inspec = rest[modelName].fields || {}
      specTransform(allspec, modelName, spec, inspec, Object.keys(inspec))
      newrest[modelName] = _.extend({}, rest[modelName], { fields: spec })

    # set all indirect owners
    Object.keys(newrest).forEach (modelName) ->
      newrest[modelName].indirectOwners = getAllIndirectOwners(specmodels, modelName)



    # avsockrad. Kör spec-transform2

    Object.keys(newrest).forEach (modelName) ->
      toDef.push([modelName, newrest[modelName]])


    Object.keys(newrest).forEach (modelName) ->
      meta[modelName] = meta[modelName] || {}
      meta[modelName].owners = _.pairs(newrest[modelName].owners).map ([sing, plur]) -> { sing: sing, plur: plur }

      meta[modelName].fields = [
        name: 'id'
        readonly: true
        required: false
        type: 'string'
      ]

      meta[modelName].fields = meta[modelName].fields.concat _.pairs(specmodels[modelName].fields).filter(([k, v]) -> v.type != 'hasMany').map ([k, v]) -> {
        name: k
        readonly: k == '_id'
        required: !!v.require
        type: v.type
      }

      meta[modelName].fields = meta[modelName].fields.concat _.pairs(newrest[modelName].owners).map ([k, v]) ->
        name: k
        readonly: true
        required: true
        type: 'string'

      meta[modelName].fields = meta[modelName].fields.concat _.pairs(newrest[modelName].indirectOwners).map ([k, v]) ->
        name: k
        readonly: true
        required: true
        type: 'string'

      meta[modelName].fields = _.sortBy meta[modelName].fields, (x) -> x.name


      apa = (modelName) -> _.pairs(specmodels[modelName].fields).filter(([key, value]) -> value.type == 'hasMany')
      ownMany = apa(modelName).map ([k, v]) -> { ref: v.model, name: k, inverseName: v.inverseName }
      otherMany = Object.keys(specmodels).map (mn) ->
        fd = apa(mn).filter ([k, v]) -> v.model == modelName
        fd.map ([k, v]) -> { ref: mn, name: v.inverseName, inverseName: k }
      meta[modelName].manyToMany = _.flatten ownMany.concat(otherMany)

    Object.keys(meta).forEach (metaName) ->
      meta[metaName].owns = _.flatten(Object.keys(meta).map (mn) -> meta[mn].owners.filter((x) -> x.plur == metaName).map (x) -> { name: mn, field: x.sing })

    toDef.forEach ([name, conf]) ->
      f1(name, conf)

    toDef.forEach ([name, conf]) ->
      f2(name, conf)

    toDef.forEach ([name, conf]) ->
      meta[name] = meta[name] || {}
      meta[name].defaultSort = conf.defaultSort



  f1 = (name, conf) ->
    spec = conf.fields
    owners = conf.owners

    # set owners
    Object.keys(owners).forEach (ownerName) ->
      spec[ownerName] =
        type: ObjectId
        ref: owners[ownerName]
        required: true
        'x-owner': true


  f2 = (name, conf) ->
    spec = conf.fields
    owners = conf.owners

    Object.keys(conf.indirectOwners).forEach (p) ->
      spec[p] =
        type: ObjectId
        ref: conf.indirectOwners[p]
        required: true
        'x-indirect-owner': true

    Object.keys(spec).forEach (fieldName) ->
      if spec[fieldName].ref?
        spec[fieldName].type = ObjectId




  toDef = []

  api.getMeta = (modelName) ->
    fields: meta[modelName].fields
    owns: meta[modelName].owns
    owners: meta[modelName].owners
    manyToMany: meta[modelName].manyToMany

  api.getModels = -> specmodels



  # checking that nullable relations are set to values that exist
  nullablesValidation = (schema) -> (next) ->

    self = this
    paths = schema.paths
    outers = Object.keys(paths).filter((x) -> paths[x].options.type == ObjectId && typeof paths[x].options.ref == 'string' && !paths[x].options['x-owner']).map (x) ->
      plur: paths[x].options.ref
      sing: x
      validation: paths[x].options['x-validation']

    # setting to null is always ok
    nonNullOuters = outers.filter (x) -> self[x.sing]?

    async.forEach nonNullOuters, (o, callback) ->
      api.getOne o.plur, { id: self[o.sing] }, (err, data) ->
        if err || !data
          callback(new Error("Invalid pointer"))
        else if o.validation
          o.validation self, data, (err) ->
            callback(if err then new Error(err))
        else
          callback()
    , next

  preRemoveCascadeNonNullable = (owner, id, next) ->
    manys = api.getMeta(owner.modelName).manyToMany

    async.forEach manys, (many, callback) ->
      obj = _.object([[many.inverseName, id]])
      models[many.ref].update obj, { $pull: obj }, callback
    , (err) ->

      # what to do on error?

      flattenedModels = api.getMeta(owner.modelName).owns

      async.forEach flattenedModels, (mod, callback) ->
        internalListSub mod.name, mod.field, id, (err, data) ->
          async.forEach data, (item, callback) ->
            item.remove callback
          , callback
      , next



  preRemoveCascadeNullable = (owner, id, next) ->
    ownedModels = Object.keys(models).map (modelName) ->
      paths = models[modelName].schema.paths
      Object.keys(paths).filter((x) -> paths[x].options.type == ObjectId && paths[x].options.ref == owner.modelName && !paths[x].options['x-owner']).map (x) ->
        name: modelName
        field: x

    flattenedModels = _.flatten ownedModels

    async.forEach flattenedModels, (mod, callback) ->
      internalListSub mod.name, mod.field, id, (err, data) ->
        async.forEach data, (item, callback) ->
          item[mod.field] = null
          item.save()
          callback()
        , callback
    , next

  api
