async = require 'async'
_ = require 'underscore'
tools = require './manikin-tools'

exports.create = ->
  specmodels = {}
  metamodels = null
  db = null

  nextIdForModel = (model) -> model + '-' + (db[model].length + 1).toString()

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

  delAllMatches = (model, config) ->
    toDeletes = db[model].filter(objectSubset(config))

    toDeletes.forEach (toDelete) ->

      db[model] = db[model].filter (x) -> x.id != toDelete.id

      # hitta alla many-to-many-relationer som den hör till och ta bort dom därifrån
      metamodels[model].manyToMany.forEach (mm) ->
        db[mm.ref].forEach (obj) ->
          obj[mm.inverseName] = obj[mm.inverseName].filter((x) -> x != toDelete.id)

      # ta bort ägda objekt rekursivt
      metamodels[model].owns.forEach (owned) ->
        delAllMatches(owned.name, _.object([[owned.field, toDelete.id]]))

  insertOps = []

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

      n1 = metamodels[model].fields.map (x) -> x.name
      n2 = Object.keys specmodels[model].indirectOwners
      n3 = Object.keys specmodels[model].owners
      n4 = metamodels[model].manyToMany.map (x) -> x.name
      nAll = n1.concat(n2).concat(n3).concat(n4)

      # Detta körs på PUT. Varför inte också köra det på post???
      # extraFields = _(Object.keys(data)).difference(nAll).sort()
      # if extraFields.length > 0
      #   return callback(new Error("Invalid fields: #{extraFields.join(', ')}"))

      obj = _(obj).pick(nAll)

      isFail = []

      Object.keys(specmodels[model].fields).filter((x) -> specmodels[model].fields[x].validate).forEach (field) ->
        v = specmodels[model].fields[field].validate
        v api, obj[field], (isOK) ->
          isFail.push(field) if !isOK

      # den här datastrukturen med felmeddelandet är ju jättekonstig. måste göra en mycket mer coherent
      if isFail.length > 0
        e = {}
        e.message = 'Validation failed'
        e.errors = {
          name: {
            path: 'name'
          }
        }
        return callback(e)

      missingOwners = metamodels[model].owners.filter (x) -> !data[x.sing]?
      if missingOwners.length > 0
        return callback(new Error('missing owner')) # should be a more precisise string

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
      toDelete = db[model].filter(objectSubset(config))

      # råkorkat att dela in det i "no such id" och "no match"
      if toDelete.length == 0
        if Object.keys(config).length == 1 && Object.keys(config)[0] == 'id'
          return callback(new Error('No such id'))
        else
          return callback(new Error('No match'))

      throw "fail3" if toDelete.length != 1

      delAllMatches(model, config)
      callback(null, toDelete[0])

    putOne: (model, data, config, callback) -> # varför har denna fyra? ska den verkligen ha det...
      obj = objectify(model, data)

      n1 = metamodels[model].fields.map (x) -> x.name
      n2 = Object.keys specmodels[model].indirectOwners
      n3 = Object.keys specmodels[model].owners
      n4 = metamodels[model].manyToMany.map (x) -> x.name
      nAll = n1.concat(n2).concat(n3).concat(n4)
      
      extraFields = _(Object.keys(data)).difference(nAll).sort()
      if extraFields.length > 0
        return callback(new Error("Invalid fields: #{extraFields.join(', ')}"))

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

      list = db[primaryModel].filter(objectSubset({ id: primaryId }))

      # råkorkat att dela in det i "no such id" och "no match"
      if list.length == 0
        if Object.keys(config).length == 1 && Object.keys(config)[0] == 'id'
          return callback(new Error('No such id'))
        else
          return callback(new Error('No match'))

      callback(null, list[0][propertyName])

    delMany: (primaryModel, primaryId, propertyName, secondaryId, callback) ->

      matches = metamodels[primaryModel].manyToMany.filter((x) -> x.name == propertyName)
      return callback(new Error('Invalid many-to-many property')) if matches.length != 1
      match = matches[0]

      list1 = db[primaryModel].filter(objectSubset({ id: primaryId }))
      list2 = db[match.ref].filter(objectSubset({ id: secondaryId }))

      list1 = list1.forEach (x) ->
        x[propertyName] = x[propertyName].filter (y) -> y != secondaryId

      list2 = list2.forEach (x) ->
        x[match.inverseName] = x[match.inverseName].filter (y) -> y != primaryId

      callback()

    postMany: (primaryModel, primaryId, propertyName, secondaryId, callback) ->

      matches = metamodels[primaryModel].manyToMany.filter((x) -> x.name == propertyName)

      return callback(new Error('Invalid many-to-many property')) if matches.length != 1
      match = matches[0]
      inverseName = match.inverseName
      secondaryModel = match.ref

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

      list1 = db[primaryModel].filter(objectSubset({ id: primaryId }))
      list2 = db[match.ref].filter(objectSubset({ id: secondaryId }))

      list1.forEach (e) ->
        e[propertyName] = e[propertyName] || []
        e[propertyName].push(secondaryId)

      list2.forEach (e) ->
        e[match.inverseName] = e[match.inverseName] || []
        e[match.inverseName].push(primaryId)

      setTimeout ->
        insertOps = insertOps.filter (x) -> !_(insertOpNow).contains(x)
        callback(null, { status: 'inserted' })
      , 1
  }

  api
