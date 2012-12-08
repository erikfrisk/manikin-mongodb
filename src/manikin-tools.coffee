"use strict"

_ = require 'underscore'



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



getAllOwners = (specmodels, modelName) ->
  owners = specmodels[modelName].owners
  indirect = _.values(owners).map (model) -> getAllOwners(specmodels, model)
  _.extend {}, owners, indirect...



getAllIndirectOwners = (specmodels, modelName) ->
  owners = specmodels[modelName].owners
  indirect = _.flatten _.values(owners).map (model) -> getAllOwners(specmodels, model)
  _.extend {}, indirect...



exports.desugar = (models) ->
  rest = {}

  Object.keys(models).forEach (modelName) ->
    spec = {}
    inspec = models[modelName].fields || {}
    desugarModel(modelName, spec, inspec, Object.keys(inspec))
    rest[modelName] = _.extend({}, models[modelName], { fields: spec })
    if !rest[modelName].owners
      rest[modelName].owners = {}

  Object.keys(rest).forEach (modelName) ->
    rest[modelName].indirectOwners = getAllIndirectOwners(rest, modelName)

  rest



exports.getMeta = (specmodels) ->
  meta = {}

  Object.keys(specmodels).forEach (modelName) ->
    meta[modelName] = meta[modelName] || {}
    meta[modelName].owners = _.pairs(specmodels[modelName].owners).map ([sing, plur]) -> { sing: sing, plur: plur }

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

    meta[modelName].fields = meta[modelName].fields.concat _.pairs(specmodels[modelName].owners).map ([k, v]) ->
      name: k
      readonly: true
      required: true
      type: 'string'

    meta[modelName].fields = meta[modelName].fields.concat _.pairs(specmodels[modelName].indirectOwners).map ([k, v]) ->
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

  meta
