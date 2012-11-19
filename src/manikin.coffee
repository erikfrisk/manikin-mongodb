async = require 'async'
_ = require 'underscore'
mongoose = require 'mongoose'
mongojs = require 'mongojs'
ObjectId = mongoose.Schema.ObjectId

exports.create = ->

  db = null
  api = {}
  models = {}
  specmodels = {}
  meta = {}

  propagate = (callback, f) ->
    (err, args...) ->
      if err
        callback(err)
      else
        f.apply(this, args)

  model = (name, schema) ->
    ss = new mongoose.Schema schema,
      strict: true
    ss.set('versionKey', false)
    mongoose.model name, ss

  api.isValidId = (id) ->
    try
      mongoose.mongo.ObjectID(id)
      true
    catch ex
      false

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



  # Connecting to db
  # ================
  api.connect = (databaseUrl, callback) ->
    mongoose.connect databaseUrl
    db = mongojs.connect databaseUrl, Object.keys(api.getModels())
    db[Object.keys(models)[0]].find (err) ->
      callback(err)


  api.close = (callback) ->
    mongoose.connection.close()
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


  getKeys = (data, target = [], prefix = '') ->
    valids = ['Array', 'String', 'Boolean', 'Date', 'Number', 'Null']

    Object.keys(data).forEach (key) ->
      if valids.some((x) -> _(data[key])['is' + x]())
        target.push(prefix + key)
      else
        getKeys(data[key], target, prefix + key + '.')

    target

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



    ownersRaw = getOwners(model)
    owners = _(ownersRaw).pluck('plur')
    ownersOwners = _(owners.map (x) -> getOwners(x)).flatten()

    if ownersOwners.length == 0
      saveFunc indata
    else
      # Should get all the owners and not just the first.
      # At the moment Im only working with single owners though, so it's for for now...
      api.getOne owners[0], { id: indata[ownersRaw[0].sing] }, (err, ownerdata) ->
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

    mm = getManyToMany(primaryModel).filter((x) -> x.name == propertyName)[0]

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

    mm = getManyToMany(primaryModel).filter((x) -> x.name == propertyName)[0]

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
      callback(null, { })
      return

    insertOpNow.forEach (op) ->
      insertOps.push(op)

    models[primaryModel].findById primaryId, propagate callback, (data) ->
      models[secondaryModel].findById secondaryId, propagate callback, (data2) ->

        datas = [data, data2]
        updated = [false, false]

        if -1 == data[propertyName].indexOf secondaryId
          data[propertyName].push secondaryId
          updated[0] = true

        if -1 == data2[inverseName].indexOf primaryId
          data2[inverseName].push primaryId
          updated[1] = true

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

          callback(err, {})


  api.getMany = (primaryModel, primaryId, propertyName, callback) ->
    models[primaryModel]
    .findOne({ _id: primaryId })
    .populate(propertyName)
    .exec (err, story) ->
      callback err, massage(story[propertyName])







  desugarModel = (modelName, tgt, src, keys) ->
    keys.forEach (key) ->
      if typeof src[key] == 'string'
        obj = {}
        obj[key] = { type: src[key] }
        desugarModel(modelName, tgt, obj, [key])
      else if !src[key].type?
        throw new Error("must assign a type: " + JSON.stringify(keys))
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
        tgt[key] = { ref: src[key].model, validation: src[key].validation }
      else if src[key].type == 'hasMany'
        tgt[key] = src[key]
        tgt[key].inverseName = src[key].inverseName || key
      else
        throw new Error("Invalid type: " + src[key].type)


  specTransform = (allspec, modelName, tgt, src, keys) ->
    keys.forEach (key) ->
      if src[key].type == 'mixed'
        tgt[key] = { type: mongoose.Schema.Types.Mixed }
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

    # avsockrad. Kör spec-transform2

    Object.keys(newrest).forEach (modelName) ->
      defModel modelName, newrest[modelName]

  defModel = (name, conf) ->

    spec = conf.fields
    owners = conf.owners

    # set owners
    Object.keys(owners).forEach (ownerName) ->
      spec[ownerName] =
        type: ObjectId
        ref: owners[ownerName]
        required: true
        'x-owner': true

    # set indirect owners (SHOULD use the full list of models, rather than depend on that indirect owners have been created already)
    Object.keys(owners).forEach (ownerName) ->
      paths = models[owners[ownerName]].schema.paths
      Object.keys(paths).filter((p) -> paths[p].options['x-owner'] || paths[p].options['x-indirect-owner']).forEach (p) ->
        spec[p] =
          type: ObjectId
          ref: paths[p].options.ref
          required: true
          'x-indirect-owner': true

    Object.keys(spec).forEach (fieldName) ->
      if spec[fieldName].ref?
        spec[fieldName].type = ObjectId

    meta[name] = { defaultSort: conf.defaultSort }

    models[name] = model name, spec

    models[name].schema.pre 'save', nullablesValidation(models[name].schema)
    models[name].schema.pre 'remove', (next) -> preRemoveCascadeNonNullable(models[name], this._id.toString(), next)
    models[name].schema.pre 'remove', (next) -> preRemoveCascadeNullable(models[name], this._id.toString(), next)




  getMetaFields = (modelName) ->
    typeMap =
      ObjectID: 'string'
      String: 'string'
      Number: 'number'
      Boolean: 'boolean'
      Date: 'date'
    paths = models[modelName].schema.paths

    typeFunc = (x) ->
      return 'boolean' if x == Boolean
      return 'date' if x == Date

    metaFields = Object.keys(paths).filter((key) -> !Array.isArray(paths[key].options.type)).map (key) ->
      name: (if key == '_id' then 'id' else key)
      readonly: key == '_id' || !!paths[key].options['x-owner'] || !!paths[key].options['x-indirect-owner']
      required: !!paths[key].options.required
      type: typeMap[paths[key].instance] || typeFunc(paths[key].options.type) || 'unknown'
    _.sortBy(metaFields, 'name')

  getOwners = (modelName) ->
    paths = models[modelName].schema.paths
    outers = Object.keys(paths).filter((x) -> paths[x].options['x-owner']).map (x) ->
      plur: paths[x].options.ref
      sing: x
    outers

  getOwnedModels = (ownerModelName) ->
    _.flatten Object.keys(models).map (modelName) ->
      paths = models[modelName].schema.paths
      Object.keys(paths).filter((x) -> paths[x].options.type == ObjectId && paths[x].options.ref == ownerModelName && paths[x].options['x-owner']).map (x) ->
        name: modelName
        field: x

  getManyToMany = (modelName) ->
    paths = models[modelName].schema.paths
    manyToMany = Object.keys(paths).filter((x) -> Array.isArray paths[x].options.type).map (x) ->
      inverseName: paths[x].options.type[0].inverseName
      ref: paths[x].options.type[0].ref
      name: x
    manyToMany

  api.getMeta = (modelName) ->
    fields: getMetaFields(modelName)
    owns: getOwnedModels(modelName)
    owners: getOwners(modelName)
    manyToMany: getManyToMany(modelName)

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
    manys = getManyToMany(owner.modelName)

    async.forEach manys, (many, callback) ->
      obj = _.object([[many.inverseName, id]])
      models[many.ref].update obj, { $pull: obj }, callback
    , (err) ->

      # what to do on error?

      flattenedModels = getOwnedModels(owner.modelName)

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
