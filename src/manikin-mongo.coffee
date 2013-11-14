async = require 'async'
_ = require 'underscore'
tools = require 'manikin-tools'



# Pure helper functions
# =============================================================================

preprocFilter = (filter) ->
  x = _.extend({}, filter)
  x._id = x.id if x.id
  delete x.id
  _.object _.pairs(x).map ([key, value]) -> [key, (if Array.isArray(value) then { $in: value } else value)]


massageOne = (x) ->
  return x if !x?
  x.id = x._id
  delete x._id
  x


massageCore = (r2) -> if Array.isArray(r2) then r2.map(massageOne) else massageOne(r2)


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
  valids = ['Array', 'String', 'Boolean', 'Date', 'Number', 'Null', 'Undefined']

  Object.keys(data).forEach (key) ->
    if valids.some((x) -> _(data[key])['is' + x]())
      target.push(prefix + key)
    else
      getKeys(data[key], target, prefix + key + '.')

  target



# Manikin constructor
# =============================================================================

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

  api = {}
  models = {}
  specmodels = {}
  metaData = null

  # Mongoose- or state-dependent helpers
  # ====================================
  makeModel = (connection, name, schema) ->
    ss = new Schema(schema, { strict: true })
    ss.set('versionKey', false)
    connection.model(name, ss, name)



  getMeta = (modelName) ->
    metaData[modelName]

  isObjectId = (val) ->
    try
      ObjectID(val)
      return true
    catch
      return false

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



  internalListSub = (model, outer, id, filter, callback) ->
    if filter[outer]? && filter[outer].toString() != id.toString()
      callback(new Error('No such id'))
      return

    filter = preprocFilter(filter)
    finalFilter = _.extend({}, filter, _.object([[outer, id]]))

    models[model].find(finalFilter, callback)



  preSaveHasOne = (owner, that, next) ->
    hasOnes = _.pairs(specmodels[owner.modelName]?.fields).filter ([key, value]) ->
      value.type == 'hasOne'
    .map ([key, value]) ->
      { property: key, model: value.model }

    async.forEach hasOnes, (hasOne, callback) ->
      if !that[hasOne.property]?
        callback()
        return

      filter = preprocFilter({ id: that[hasOne.property] })
      models[hasOne.model].findOne filter, (err, data) ->
        if err || !data?
          callback(new Error("Invalid hasOne-key for '#{hasOne.property}'"))
        else
          callback()
    , next

  preRemoveCascadeNonNullable = (owner, id, next) ->
    manys = getMeta(owner.modelName).manyToMany

    async.forEach manys, (many, callback) ->
      obj = _.object([[many.inverseName, id]])
      models[many.ref].update(obj, { $pull: obj }, callback)
    , (err) ->
      return next(err) if err # what to do on error?

      flattenedModels = getMeta(owner.modelName).owns

      async.forEach flattenedModels, (mod, callback) ->
        internalListSub mod.name, mod.field, id, {}, propagate callback, (data) ->
          async.forEach data, (item, callback) ->
            item.remove(callback)
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
      internalListSub mod.name, mod.field, id, {}, propagate callback, (data) ->
        async.forEach data, (item, callback) ->
          item[mod.field] = null
          item.save(callback)
        , callback
    , next



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
        tgt[key] = { ref: src[key].model, 'x-validation': src[key].validation, type: ObjectId }
      else if src[key].type == 'hasMany'
        tgt[key] = [{ type: ObjectId, ref: src[key].model, inverseName: src[key].inverseName }]
        allspec[src[key].model][src[key].inverseName] = [{ type: ObjectId, ref: modelName, inverseName: key }]



  defModels = (models) ->

    specmodels = tools.desugar(models)
    toDef = []
    newrest = {}

    allspec = {}
    Object.keys(specmodels).forEach (modelName) ->
      allspec[modelName] = {}

    Object.keys(specmodels).forEach (modelName) ->
      spec = allspec[modelName]
      owners = specmodels[modelName].owners || {}
      inspec = specmodels[modelName].fields || {}
      specTransform(allspec, modelName, spec, inspec, Object.keys(inspec))
      newrest[modelName] = _.extend({}, specmodels[modelName], { fields: spec })

    Object.keys(newrest).forEach (modelName) ->
      conf = newrest[modelName]

      Object.keys(conf.owners).forEach (ownerName) ->
        conf.fields[ownerName] =
          type: ObjectId
          ref: conf.owners[ownerName]
          required: true
          'x-owner': true

      Object.keys(conf.indirectOwners).forEach (p) ->
        conf.fields[p] =
          type: ObjectId
          ref: conf.indirectOwners[p]
          required: true
          'x-indirect-owner': true

      Object.keys(conf.fields).forEach (fieldName) ->
        if conf.fields[fieldName].ref?
          conf.fields[fieldName].type = ObjectId

      toDef.push([modelName, newrest[modelName]])

    metaData = tools.getMeta(specmodels)

    toDef


  getInvalidFields = (modelName, data) ->
    model = models[modelName]
    mixedFields = getMeta(modelName).fields.filter((x) -> x.type == 'mixed').map (x) -> x.name

    inputFieldsValid = getKeys(_.omit(data, mixedFields))
    inputFields = Object.keys data
    validField = Object.keys(model.schema.paths)

    vf = []
    validField.forEach (x) ->
      parts = x.split('.')
      [1..parts.length].forEach (len) ->
        vf.push(parts.slice(0, len).join('.'))

    invalidFields = _.difference(inputFieldsValid, vf)


  preprocessError = (err, msg) ->
    regex = new RegExp('Cast to ObjectId failed for value "([^\\"]*)" at path "([^\\"]*)"')

    if !err?
      return err
    else if err.toString() == 'Error: Invalid ObjectId' || err.message?.match(regex)
      new Error(msg.replace('{path}', err.message?.match(regex)[2]))
    else
      err



  # Connecting
  # ==========
  do ->
    connection = null
    lateLoadModel = null
    dbUrl = null

    api.connect = (databaseUrl, inputModels, callback) ->
      if !callback? && typeof inputModels == 'function'
        callback = inputModels
        inputModels = lateLoadModel

      onConnected = _.once (err) ->
        return callback(err) if err?

        dbUrl = databaseUrl
        if inputModels
          api.load(inputModels, callback)
        else
          callback()

      try
        connection = mongoose.createConnection(databaseUrl)
        connection.on 'error', (err) -> onConnected(err)
        connection.on 'connected', -> onConnected()
      catch ex
        onConnected(ex)


    api.close = (callback) ->
      connection.close()
      callback()

    api.connectionData = ->
      dbUrl

    api.load = (inputModels, callback) ->
      if connection == null
        lateLoadModel = inputModels
        callback()
        return

      defModels(inputModels).forEach ([name, v]) ->
        models[name] = makeModel(connection, name, v.fields)
        models[name].schema.pre 'save', nullablesValidation(models[name].schema)
        models[name].schema.pre 'remove', (next) -> preRemoveCascadeNonNullable(models[name], this._id.toString(), next)
        models[name].schema.pre 'remove', (next) -> preRemoveCascadeNullable(models[name], this._id.toString(), next)
        models[name].schema.pre 'save',   (next) -> preSaveHasOne(models[name], this, next)
      callback()


  # The five base methods
  # =====================
  api.post = (model, indata, callback) ->

    invalidFields = getInvalidFields(model, indata)
    if invalidFields.length > 0
      callback(new Error("Invalid fields: " + invalidFields.join(', ')))
      return

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


    ownersRaw = getMeta(model).owners
    owners = _(ownersRaw).pluck('plur')
    ownersOwners = _.flatten owners.map (x) -> getMeta(x).owners

    if owners.length == 0
      saveFunc indata
    else
      # Should get all the owners and not just the first.
      # At the moment Im only working with single owners though, so it's for for now...
      api.getOne owners[0], { filter: { id: indata[ownersRaw[0].sing] } }, propagate callback, (ownerdata) ->
        paths = models[owners[0]].schema.paths
        metaFields = Object.keys(paths).filter (key) -> !!paths[key].options['x-owner'] || !!paths[key].options['x-indirect-owner']
        metaFields.forEach (key) ->
          indata[key] = ownerdata[key]
        saveFunc indata

  api.list = (model, filter, callback) ->
    filter = preprocFilter(filter)

    monModel = specmodels[model]

    return callback(new Error("No model named #{model}")) if !monModel?

    defaultSort = monModel.defaultSort

    rr = models[model].find(filter)
    if defaultSort?
      rr = rr.sort _.object [[defaultSort, 'asc']]
    rr.exec(massaged(callback))

  api.getOne = (model, config, callback) ->
    filter = preprocFilter(config.filter || {})

    models[model].findOne filter, (err, data) ->
      if err
        callback(preprocessError(err, 'No such id'))
      else if !data?
        callback(new Error('No match'))
      else
        callback null, massage(data)

  api.delOne = (model, filter, callback) ->
    filter = preprocFilter(filter)

    models[model].findOne filter, (err, d) ->
      if err
        callback(preprocessError(err, 'No such id'))
      else if !d?
        callback(new Error('No such id'))
      else
        d.remove (err) ->
          callback err, if !err then massage(d)

  api.putOne = (modelName, data, filter, callback) ->
    model = models[modelName]
    filter = preprocFilter(filter)
    inputFields = Object.keys data

    invalidFields = getInvalidFields(modelName, data)

    if invalidFields.length > 0
      callback(new Error("Invalid fields: " + invalidFields.join(', ')))
      return

    model.findOne filter, (err, d) ->
      if err?
        if err.message == 'Invalid ObjectId' || err.message.match('Cast to ObjectId failed for value "[^\\"]*" at path "_id"')
          callback(new Error("No such id"))
        else
          callback(err)
        return

      if !d?
        callback(new Error("No such id"))
        return

      inputFields.forEach (key) ->
        d[key] = data[key]

      d.save (err) ->
        callback(preprocessError(err, "Invalid hasOne-key for '{path}'"), if err then null else massage(d))



  # The many-to-many methods
  # ========================
  api.delMany = (primaryModel, primaryId, propertyName, secondaryId, callback) ->

    if !isObjectId(primaryId)
      return callback(new Error("Could not find an instance of '#{primaryModel}' with id '#{primaryId}'"))

    mm = getMeta(primaryModel).manyToMany.filter((x) -> x.name == propertyName)[0]

    if !mm?
      callback(new Error('Invalid many-to-many property'))
      return

    secondaryModel = mm.ref
    inverseName = mm.inverseName

    if !isObjectId(secondaryId)
      return callback(new Error("Could not find an instance of '#{secondaryModel}' with id '#{secondaryId}'"))

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

    if !isObjectId(primaryId)
      return callback(new Error("Could not find an instance of '#{primaryModel}' with id '#{primaryId}'"))

    mm = getMeta(primaryModel).manyToMany.filter((x) -> x.name == propertyName)[0]

    if !mm?
      callback(new Error('Invalid many-to-many property'))
      return

    secondaryModel = mm.ref
    inverseName = mm.inverseName

    if !isObjectId(secondaryId)
      return callback(new Error("Could not find an instance of '#{secondaryModel}' with id '#{secondaryId}'"))

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
      models[item.primaryModel].findById(item.primaryId, callback)
    , propagate callback, (datas) ->

      updated = [false, false]

      insertOpNow.forEach (conf, i) ->
        if -1 == datas[i][conf.propertyName].indexOf(conf.secondaryId)
          datas[i][conf.propertyName].push(conf.secondaryId)
          updated[i] = true

      async.forEach [0, 1], (index, callback) ->
        if updated[index]
          datas[index].save(callback)
        else
          callback()
      , (err) ->

        if err
          # how to handle if one of these manages to save, but not the other?
          # the database will end up in an invalid state! is it possible to do some kind of transaction?
          # simulate such a failure and solve it using two phase commits: http://docs.mongodb.org/manual/tutorial/perform-two-phase-commits
          return callback(err)

        insertOps = insertOps.filter (x) -> !_(insertOpNow).contains(x)

        callback(null, { status: (if updated.some((x) -> x) then 'inserted' else 'already inserted') })



  api.getMany = (primaryModel, primaryId, propertyName, filter, callback) ->

    if !isObjectId(primaryId)
      return callback(new Error("Could not find an instance of '#{primaryModel}' with id '#{primaryId}'"))

    # backwards compatibility
    if !callback?
      callback = filter
      filter = {}

    mm = getMeta(primaryModel).manyToMany.filter((x) -> x.name == propertyName)[0]

    if !mm?
      callback(new Error('Invalid many-to-many property'))
      return

    {ref, inverseName} = mm

    ownerFilter = _.object([[inverseName, primaryId]])
    finalFilter = _.extend({}, filter, ownerFilter)

    models[ref].find finalFilter, propagate callback, (data) ->
      callback(null, massage(data))



  # Return the public API
  # =====================
  api
