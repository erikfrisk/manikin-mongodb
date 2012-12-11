async = require 'async'
_ = require 'underscore'
tools = require './manikin-tools'

exports.create = ->
  specmodels = {}
  metamodels = null
  db = null

  nextIdForModel = (model) -> (db[model].length + 1).toString()

  deepEquals = (a, b) -> JSON.stringify(a) == JSON.stringify(b)

  ISODateString = (d) ->
    pad = (n) -> if n < 10 then '0' + n else n
    pad2 = (n) -> if n < 10 then '00' + n else if n < 100 then '0' + n else n

    d.getUTCFullYear() + '-' +
    pad(d.getUTCMonth() + 1) + '-' +
    pad(d.getUTCDate()) + 'T' +
    pad(d.getUTCHours()) + ':' +
    pad(d.getUTCMinutes()) + ':' +
    pad(d.getUTCSeconds()) + '.' +
    pad2(d.getUTCMilliseconds()) + 'Z'

  formatDate = (date) -> ISODateString(new Date(date))

  objectify = (model, data) ->
    id = nextIdForModel(model)
    fields = metamodels[model].fields
    indirectOwners = specmodels[model].indirectOwners
    owners = specmodels[model].owners
    obj = _.extend({}, data, { id: id })

    fields.forEach (field) ->
      if field.type == 'date'
        obj[field.name] = formatDate obj[field.name]
      else
        null

    if Object.keys(indirectOwners).length > 0
      vals = _(owners).values()[0]
      keys = _(owners).keys()[0]
      ff = db[vals].filter(objectSubset({ id: obj[keys] }))
      if ff.length != 1 then throw "somethings wrong"
      obj = _.extend({}, obj, _(ff[0]).pick(Object.keys(indirectOwners)))

    metamodels[model].manyToMany.forEach (m) ->
      if !obj[m.name]?
        obj[m.name] = []

    obj

  objectSubset = (filter) -> (obj) ->
    filterKeys = Object.keys(filter)
    o = _(obj).pick(filterKeys...)
    x = deepEquals(o, filter)
    x
    
    

  api = {
    connect: (connectionData, models, callback) ->
      if !_.isObject(connectionData)
        return callback(new Error('Connection data must be an object'))

      db = connectionData
      specmodels = tools.desugar(models)
      metamodels = tools.getMeta(specmodels)

      Object.keys(specmodels).forEach (modelName) ->
        db[modelName] = []

      callback()

    close: (callback) ->
      callback()

    post: (model, data, callback) ->
      obj = objectify(model, data)
      db[model].push(obj)
      callback(null, obj)

    list: (model, config, callback) ->
      data = db[model]
      sortParam = specmodels[model].defaultSort
      data = _.sortBy(data, sortParam) if sortParam?
      callback(null, data)

    getOne: (model, config, callback) ->
      list = db[model].filter(objectSubset(config.filter))

      # råkorkat att dela in det i "no such id" och "no match"
      if list.length == 0
        if Object.keys(config.filter).length == 1 && Object.keys(config.filter)[0] == 'id'
          return callback(new Error('No such id'))
        else
          return callback(new Error('No match'))

      callback(null, list[0])

    delOne: (model, config, callback) ->
      list = db[model].filter(objectSubset(config))

      # råkorkat att dela in det i "no such id" och "no match"
      if list.length == 0
        if Object.keys(config).length == 1 && Object.keys(config)[0] == 'id'
          return callback(new Error('No such id'))
        else
          return callback(new Error('No match'))

      callback(null, list[0])

    putOne: (model, data, config, callback) -> # varför har denna fyra? ska den verkligen ha det...
      obj = objectify(model, data)

      list = db[model].filter(objectSubset(config))

      # råkorkat att dela in det i "no such id" och "no match"
      if list.length == 0
        if Object.keys(config).length == 1 && Object.keys(config)[0] == 'id'
          return callback(new Error('No such id'))
        else
          return callback(new Error('No match'))

      _.extend(list[0], _(obj).omit('id'))

      callback(null, list[0])

    getMany: (primaryModel, primaryId, propertyName, callback) ->
      callback()

    delMany: (primaryModel, primaryId, propertyName, secondaryId, callback) ->
      callback()

    postMany: (primaryModel, primaryId, propertyName, secondaryId, callback) ->
      callback()
  }

  api
