async = require 'async'
_ = require 'underscore'
mongoose = require 'mongoose'
underline = require 'underline'
mongojs = require 'mongojs'
ObjectId = mongoose.Schema.ObjectId


exports.create = (databaseUrl) ->

  db = null
  api = {}
  models = {}
  api.ObjectId = ObjectId

  propagate = (callback, f) ->
    (err, args...) ->
      if err
        callback(err)
      else
        f.apply(this, args)

  model = (name, schema) ->
    ss = new mongoose.Schema schema,
      strict: true
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
    db = mongojs.connect databaseUrl, api.getModels()
    db[Object.keys(models)[0]].find (err) ->
      callback(err)



  # The five base methods
  # =====================
  api.list = (model, filter, callback) ->
    if !callback?
      callback = filter
      filter = {}

    filter = preprocFilter(filter)

    models[model].find filter, massaged(callback)

  api.getOne = (model, filter, callback) ->
    if !callback?
      callback = filter
      filter = {}

    filter = preprocFilter(filter)

    models[model].findOne filter, (err, data) ->
      if err
        if err.toString() == 'Error: Invalid ObjectId'
          callback("No such id")
        else
          callback(err)
        return
      callback((if !data? then "No such id"), massage(data))

  api.delOne = (model, filter, callback) ->
    if !callback?
      callback = filter
      filter = {}

    filter = preprocFilter(filter)

    models[model].findOne filter, propagate callback, (d) ->
      if !d?
        callback "No such id"
      else
        d.remove (err) ->
          callback err, if !err then massage(d)

  api.putOne = (modelName, data, filter, callback) ->
    if !callback?
      callback = filter
      filter = {}

    filter = preprocFilter(filter)

    model = models[modelName]
    inputFields = Object.keys data
    validField = Object.keys(model.schema.paths)

    invalidFields = _.difference(inputFields, validField)

    if invalidFields.length > 0
      callback("Invalid fields: " + invalidFields.join(', '))
      return

    model.findOne filter, propagate callback, (d) ->
      if !d?
        callback "No such id"
        return

      inputFields.forEach (key) ->
        d[key] = data[key]

      d.save (err) ->
        callback(err, if err then null else massage(d))




  # Sub-methods
  # ===========
  api.post = (model, data, callback) ->
    new models[model](data).save (err) ->
      if err && err.code == 11000
        fieldMatch = err.err.match(/\$([a-zA-Z]+)_1/)
        valueMatch = err.err.match(/"([a-zA-Z]+)"/)
        if fieldMatch && valueMatch
          callback("Duplicate value '#{valueMatch[1]}' for #{fieldMatch[1]}")
        else
          callback("Unique constraint violated")
      else
        massaged(callback).apply(this, arguments)

  internalListSub = (model, outer, id, filter, callback) ->
    if !callback?
      callback = filter
      filter = {}

    if filter[outer]? && filter[outer].toString() != id.toString()
      callback 'No such id'
      return

    filter = preprocFilter(filter)
    finalFilter = _.extend({}, filter, underline.makeObject(outer, id))

    models[model].find finalFilter, callback




  # The many-to-many methods
  # ========================
  api.delMany = (primaryModel, primaryId, propertyName, secondaryModel, secondaryId, callback) ->
    models[primaryModel].findById primaryId, propagate callback, (data) ->
      conditions = { _id: primaryId }
      update = { $pull: underline.makeObject(propertyName, secondaryId) }
      options = { }
      models[primaryModel].update conditions, update, options, (err, numAffected) ->
        callback(err)

  api.postMany = (primaryModel, primaryId, propertyName, secondaryModel, secondaryId, callback) ->
    models[primaryModel].findById primaryId, propagate callback, (data) ->
      models[secondaryModel].findById secondaryId, propagate callback, () ->

        if -1 == data[propertyName].indexOf secondaryId
          data[propertyName].push secondaryId

        data.save (err) ->
          callback(err, {})

  api.getMany = (primaryModel, primaryId, propertyName, callback) ->
    models[primaryModel]
    .findOne({ _id: primaryId })
    .populate(propertyName)
    .run (err, story) ->
      callback err, massage(story[propertyName])

  api.getManyBackwards = (model, id, propertyName, callback) ->
    db[model].find underline.makeObject(propertyName, new db.bson.ObjectID(id.toString())), (err, result) ->
      callback(err, massage(result))






  specTransform = (tgt, src, keys) ->
    keys.forEach (key) ->
      if !src[key].type?
        throw "must assign a type: " + JSON.stringify(keys)
      else if src[key].type == 'nested'
        tgt[key] = {}
        specTransform(tgt[key], src[key], _.without(Object.keys(src[key]), 'type'))
      else if src[key].type == 'string'
        tgt[key] = { type: String, required: !!src[key].required }
        tgt[key].default = src[key].default if src[key].default?
        tgt[key].index = src[key].index if src[key].index?
        tgt[key].unique = src[key].unique if src[key].unique?
        tgt[key].validate = src[key].validate if src[key].validate?
      else if src[key].type == 'number'
        tgt[key] = { type: Number, required: !!src[key].required }
        tgt[key].default = src[key].default if src[key].default?
        tgt[key].index = src[key].index if src[key].index?
        tgt[key].unique = src[key].unique if src[key].unique?
      else if src[key].type == 'boolean'
        tgt[key] = { type: Boolean, required: !!src[key].required }
        tgt[key].default = src[key].default if src[key].default?
        tgt[key].index = src[key].index if src[key].index?
        tgt[key].unique = src[key].unique if src[key].unique?
      else if src[key].type == 'hasOne'
        tgt[key] = { ref: src[key].model, 'x-validation': src[key].validation }
      else if src[key].type == 'hasMany'
        tgt[key] = [{ type: ObjectId, ref: src[key].model }]
      else
        throw "Invalid type: " + src[key].type

  api.defModel = (name, conf) ->

    spec = {}
    owners = conf.owners || {}
    inspec = conf.fields || {}
    specTransform(spec, inspec, Object.keys(inspec))

    # set owners
    Object.keys(owners).forEach (ownerName) ->
      spec[ownerName] =
        type: ObjectId
        ref: owners[ownerName]
        'x-owner': true

    # set indirect owners (SHOULD use the full list of models, rather than depend on that indirect owners have been created already)
    Object.keys(owners).forEach (ownerName) ->
      paths = models[owners[ownerName]].schema.paths
      Object.keys(paths).filter((p) -> paths[p].options['x-owner']).forEach (p) ->
        spec[p] =
          type: ObjectId
          ref: paths[p].options.ref
          'x-indirect-owner': true

    Object.keys(spec).forEach (fieldName) ->
      if spec[fieldName].ref?
        spec[fieldName].type = ObjectId

    models[name] = model name, spec

    models[name].schema.pre 'save', nullablesValidation(models[name].schema)
    models[name].schema.pre 'remove', (next) -> preRemoveCascadeNonNullable(models[name], this._id.toString(), next)
    models[name].schema.pre 'remove', (next) -> preRemoveCascadeNullable(models[name], this._id.toString(), next)




  api.getMetaFields = (modelName) ->
    typeMap =
      ObjectID: 'string'
      String: 'string'
      Number: 'number'
    paths = models[modelName].schema.paths
    metaFields = Object.keys(paths).map (key) ->
      name: (if key == '_id' then 'id' else key)
      readonly: key == '_id' || !!paths[key].options['x-owner'] || !!paths[key].options['x-indirect-owner']
      type: typeMap[paths[key].instance] || 'unknown'
    _.sortBy(metaFields, 'name')

  api.getOwners = (modelName) ->
    paths = models[modelName].schema.paths
    outers = Object.keys(paths).filter((x) -> paths[x].options['x-owner']).map (x) ->
      plur: paths[x].options.ref
      sing: x
    outers

  api.getOwnedModels = (ownerModelName) ->
    _.flatten Object.keys(models).map (modelName) ->
      paths = models[modelName].schema.paths
      Object.keys(paths).filter((x) -> paths[x].options.type == ObjectId && paths[x].options.ref == ownerModelName && paths[x].options['x-owner']).map (x) ->
        name: modelName
        field: x

  api.getManyToMany = (modelName) ->
    paths = models[modelName].schema.paths
    manyToMany = Object.keys(paths).filter((x) -> Array.isArray paths[x].options.type).map (x) ->
      ref: paths[x].options.type[0].ref
      name: x
    manyToMany


  api.getModels = () ->
    Object.keys(models)



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

    flattenedModels = api.getOwnedModels(owner.modelName)

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
