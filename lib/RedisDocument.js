/**
 * Module dependencies
 */

var util = require('util')
var async = require('async')
var getDeepProperty = require('modinha').getDeepProperty

/**
 * Constructor mixin
 */

function RedisDocument () {}

/**
 * List
 */

RedisDocument.list = function (options, callback) {
  var Model = this
  var collection = Model.collection
  var client = Model.__client

  // optional options argument
  if (!callback) {
    callback = options
    options = {}
  }

  // assign the default index if none is provided
  var index = options.index || collection + ':created'

  // determine the order to get a range of ids
  var range = ((options.order && options.order === 'normal')
    ? 'zrange'
    : 'zrevrange') ||
    'zrevrange'

  // default page and size
  var page = options.page || 1
  var size = options.size || 50

  // calculate start and end index
  // for the sorted set range lookup
  var startIndex = (size * (page - 1))
  var endIndex = (startIndex + size) - 1

  // get a range of ids from the index
  client[range](index, startIndex, endIndex, function (err, ids) {
    if (err) { return callback(err) }

    // handle empty results
    if (!ids || ids.length === 0) {
      return callback(null, [])
    }

    // get by id
    Model.get(ids, options, function (err, instances) {
      if (err) { return callback(err) }
      callback(null, instances)
    })
  })
}

/**
 * Get
 */

RedisDocument.get = function (ids, options, callback) {
  var Model = this
  var collection = Model.collection
  var client = Model.__client

  // optional options argument
  if (!callback) {
    callback = options
    options = {}
  }

  // return an object instead of an array
  // if the first argument is a string
  if (typeof ids === 'string') {
    options.first = true
  }

  // don't call hmget with undefined ids
  if (!ids) {
    return callback(null, null)
  }

  // don't call hmget with an empty array
  if (Array.isArray(ids) && ids.length === 0) {
    return callback(null, [])
  }

  // if redis responds with undefined or null
  // values, initialization should provide null
  // instead of an instance, and defaults should
  // not be generated
  options.nullify = true
  options.defaults = false

  // send redis the hash multiget command
  client.hmget(collection, ids, function (err, result) {
    if (err) { return callback(err) }
    callback(null, Model.initialize(result, options))
  })
}

/**
 * Insert
 */

RedisDocument.insert = function (data, options, callback) {
  var Model = this
  var collection = Model.collection
  var uniqueId = Model.uniqueId
  var instance = Model.initialize(data, { private: true })
  var validation = instance.validate()
  var client = Model.__client

  // optional options
  if (!callback) {
    callback = options
    options = {}
  }

  // handle invalid data
  if (!validation.valid) { return callback(validation) }

  Model.enforceUnique(instance, function (err) {
    if (err) { return callback(err) }

    // batch operations
    var multi = client.multi()

    // store the instance
    multi.hset(collection, instance[uniqueId], Model.serialize(instance))

    // index the instance
    Model.index(multi, instance)

    // execute the set of ops
    multi.exec(function (err, result) {
      if (err) { return callback(err) }
      callback(null, Model.initialize(instance, options))
    })
  })
}

/**
 * Replace
 */

RedisDocument.replace = function (id, data, options, callback) {
  var Model = this
  var collection = Model.collection
  var uniqueId = Model.uniqueId
  var client = Model.__client

  // optional options
  if (!callback) {
    callback = options
    options = {}
  }

  // Get the existing instance so we can reindex
  Model.get(id, { private: true }, function (err, original) {
    if (err) { return callback(err) }

    // unknown document
    if (!original) {
      return callback(null, null)
    }

    // intialize the provided data and ensure
    // the unique id of the instance matches
    // the id argument
    var instance = Model.initialize(data, { private: true })
    instance._id = id

    // validate the instance
    var validation = instance.validate()

    // handle invalid data
    if (!validation.valid) {
      return callback(validation)
    }

    Model.enforceUnique(instance, function (err) {
      if (err) { return callback(err) }

      // batch operations
      var multi = client.multi()

      // store the instance
      multi.hset(collection, instance[uniqueId], Model.serialize(instance))

      // index the instance
      Model.reindex(multi, instance, original)

      // execute the set of ops
      multi.exec(function (err, result) {
        if (err) { return callback(err) }
        callback(null, Model.initialize(instance, options))
      })
    })
  })
}

/**
 * Patch
 */

RedisDocument.patch = function (id, data, options, callback) {
  var Model = this
  var collection = Model.collection
  var uniqueId = Model.uniqueId
  var client = Model.__client

  // optional options
  if (!callback) {
    callback = options
    options = {}
  }

  // get the existing data
  Model.get(id, { private: true }, function (err, instance) {
    if (err) { return callback(err) }

    // not found?
    if (!instance) { return callback(null, null) }

    // copy the original (for reindexing)
    var original = Model.initialize(instance, { private: true })

    // merge the new values into the instance
    // without generating default values
    options.defaults = false
    instance.merge(data, options)

    // update the timestamp
    instance.modified = Model.defaults.timestamp()

    // validate the mutated instance
    var validation = instance.validate()
    if (!validation.valid) { return callback(validation) }

    Model.enforceUnique(instance, function (err) {
      if (err) { return callback(err) }

      // batch operations
      var multi = client.multi()

      // store the instance
      multi.hset(collection, instance[uniqueId], Model.serialize(instance))

      // index the instance
      Model.reindex(multi, instance, original)

      // execute the set of ops
      multi.exec(function (err, result) {
        if (err) { return callback(err) }
        callback(null, Model.initialize(instance, options))
      })
    })
  })
}

/**
 * Delete
 */

RedisDocument.delete = function (id, callback) {
  var Model = this
  var client = Model.__client

  // Get the object so that it can be deindexed
  Model.get(id, { private: true }, function (err, result) {
    if (err) { return callback(err) }

    // not found
    if (!result) { return callback(null, null) }

    // batch operations
    var multi = client.multi()

    // remove the instance(s)
    multi.hdel(Model.collection, id)

    // leave no trace in the indexes
    if (!(result instanceof Array)) { result = [result] }
    result.forEach(function (instance) {
      Model.deindex(multi, instance)
    })

    // execute the set of ops
    multi.exec(function (err, result) {
      if (err) { return callback(err) }
      callback(null, true)
    })
  })
}

/**
 * Index
 *
 * Takes a redis multi object and a model instance.
 * Iterate through the schema (does not currently
 * support nested properties) and add appropriate
 * indexing operations to the batch, if any.
 */

RedisDocument.index = function (multi, data) {
  var Model = this

  Model.__indices.forEach(function (config) {
    // hash index
    if (config.type === 'hash') {
      var key = (Array.isArray(config.key))
        ? Model.indexKey(config.key, data)
        : config.key
      var field = (Array.isArray(config.field))
        ? Model.indexKey(config.field, data)
        : getDeepProperty(data, config.field.split('.'))
      var value = getDeepProperty(data, config.value.split('.'))

      if (field) {
        multi.hset(key, field, value)
      }
    }

    // sorted set index
    if (config.type === 'sorted') {
      key = Model.indexKey(config.key, data)
      var score = data[config.score]
      var member = data[config.member]

      multi.zadd(key, score, member)
    }
  })
}

/**
 * Deindex
 *
 * Takes a redis multi object and an instance.
 * Reverse of RedisDocument.index().
 */

RedisDocument.deindex = function (multi, data) {
  var Model = this

  Model.__indices.forEach(function (config) {
    if (config.type === 'hash') {
      var key = (Array.isArray(config.key))
        ? Model.indexKey(config.key, data)
        : config.key
      var field = (Array.isArray(config.field))
        ? Model.indexKey(config.field, data)
        : getDeepProperty(data, config.field.split('.'))

      multi.hdel(key, field)
    }

    if (config.type === 'sorted') {
      key = Model.indexKey(config.key, data)
      var member = data[config.member]

      multi.zrem(key, member)
    }
  })
}

/**
 * Reindex
 */

RedisDocument.reindex = function (multi, data, orig) {
  var Model = this

  Model.__indices.forEach(function (config) {
    if (config.type === 'hash') {
      var key = (Array.isArray(config.key))
        ? Model.indexKey(config.key, data)
        : config.key
      var newField = (Array.isArray(config.field))
        ? Model.indexKey(config.field, data)
        : data[config.field]
      var oldField = (Array.isArray(config.field))
        ? Model.indexKey(config.field, orig)
        : orig[config.field]
      var newValue = data[config.value]
      var oldValue = orig[config.value]
      var changed = (newField !== oldField ||
        newValue !== oldValue)

      if (changed) {
        multi.hdel(key, oldField)
        if (newField !== undefined) {
          multi.hset(key, newField, newValue)
        }
      }
    }

    if (config.type === 'sorted') {
      var oldKey = Model.indexKey(config.key, orig)
      var newKey = Model.indexKey(config.key, data)
      var oldScore = orig[config.score]
      var newScore = data[config.score]
      var oldMember = orig[config.member]
      var newMember = data[config.member]
      changed = (oldKey !== newKey ||
        oldMember !== newMember ||
        oldScore !== newScore)

      if (changed) {
        multi.zrem(oldKey, oldMember)
        multi.zadd(newKey, newScore, newMember)
      }
    }
  })
}

/**
 * Replace placeholders in index name with real values
 */

RedisDocument.indexKey = function makekey (args, data) {
  var key = args[0]
  var params = args.slice(1)
  var i = 0

  return key.replace(/\#|\$/g, function (match) {
    var sub

    // replace with the parameter directly
    if (match === '#') {
      sub = params[i]
    }

    // replace with the value obtained by using
    // the parameter as a key in the data arg
    if (match === '$') {
      if (Array.isArray(params[i])) {
        var k = RedisDocument.indexKey(params[i], data)
        sub = getDeepProperty(data, k.split('.'))
      } else {
        sub = getDeepProperty(data, params[i].split('.'))
      }
    }

    i++; return sub
  })
}

RedisDocument.indexValue = function indexValue (args, data) {
  var key = this.indexKey(args, data)
  return getDeepProperty(data, key.split(','))
}

/**
 * Define index
 */

RedisDocument.defineIndex = function (config) {
  this.__indices.push(config)
}

/**
 * Define unique index
 */

RedisDocument.indexUnique = function (property) {
  var Model = this

  Model.defineIndex({
    type: 'hash',
    key: Model.collection + ':' + property,
    field: property,
    value: Model.uniqueId
  })
}

/**
 * Define secondary index
 */

RedisDocument.indexSecondary = function (property, score) {
  var Model = this

  Model.defineIndex({
    type: 'sorted',
    key: [Model.collection + ':#:$', property, property],
    score: score || 'modified',
    member: Model.uniqueId
  })
}

/**
 * Define reference index
 */

RedisDocument.indexReference = function (property, reference, score) {
  var Model = this

  Model.defineIndex({
    type: 'sorted',
    key: [reference.collection + ':$:' + Model.collection, property],
    score: score || 'created',
    member: Model.uniqueId
  })
}

/**
 * Define order index
 */

RedisDocument.indexOrder = function (score) {
  var Model = this

  Model.defineIndex({
    type: 'sorted',
    key: [Model.collection + ':' + score],
    score: score,
    member: Model.uniqueId
  })
}

/**
 * Enforce unique values
 */

RedisDocument.enforceUnique = function (data, callback) {
  var Model = this
  var schema = Model.schema
  var checks = []

  Object.keys(schema).forEach(function (key) {
    var property = schema[key]

    if (data.hasOwnProperty(key) && property && property.unique) {
      checks.push(function (done) {
        var method = 'getBy' + key.charAt(0).toUpperCase() + key.slice(1)
        Model[method](data[key], function (err, instance) {
          if (err) { return done(err) }

          // Invoke the callback with an error if a
          // different object exists with the indexed
          // value.
          if (instance && instance._id !== data._id) {
            return done(new UniqueValueError(key))
          }

          done(null)
        })
      })
    }
  })

  async.parallel(checks, function (err) {
    if (err) { return callback(err) }
    callback(null)
  })
}

/**
 * UniqueValueError
 */

function UniqueValueError (property) {
  this.name = 'UniqueValueError'
  this.message = property + ' must be unique'
  this.statusCode = 400
}

util.inherits(UniqueValueError, Error)
RedisDocument.UniqueValueError = UniqueValueError

/**
 * Intersects
 *
 * Defines a many to many relationship between two models
 *
 * lcollection is the collection name of the model on the left side
 * rcollection is the collection name of the model on the right side
 * ccollection is the camelized collection name for method definition
 */

RedisDocument.intersects = function (collection, unique) {
  var Model = this
  var lcollection = Model.collection
  var rcollection = collection
  var ccollection = rcollection.charAt(0).toUpperCase() +
    rcollection.slice(1)
  var lunique = Model.uniqueId
  var runique = '_id'

  /**
   * Optional arguments
   */

  if (arguments.length === 2) { runique = arguments['1'] }
  if (arguments.length === 3) { lunique = arguments['1']; runique = arguments['2'] }

  /**
   * Create mutual relationship (static)
   */

  Model['add' + ccollection] = function (lobject, robject, callback) {
    var multi = Model.__client.multi()
    var lid = (typeof lobject === 'object') ? lobject[lunique] : lobject
    var rid = (typeof robject === 'object') ? robject[runique] : robject
    var lkey = lcollection + ':' + lid + ':' + rcollection
    var rkey = rcollection + ':' + rid + ':' + lcollection
    var score = Date.now()
    var lscore = lobject.created || score
    var rscore = robject.created || score

    multi.zadd(lkey, rscore, rid)
    multi.zadd(rkey, lscore, lid)
    multi.exec(function (err, result) {
      if (err) { return callback(err) }
      callback(null, result)
    })
  }

  /**
   * Create mutual relationship (instance)
   */

  Model.prototype['add' + ccollection] = function (robject, callback) {
    Model['add' + ccollection](this, robject, callback)
  }

  /**
   * Destroy mutual relationship (static)
   */

  Model['remove' + ccollection] = function (lobject, robject, callback) {
    var multi = Model.__client.multi()
    var lid = (typeof lobject === 'object') ? lobject[lunique] : lobject
    var rid = (typeof robject === 'object') ? robject[runique] : robject
    var lkey = lcollection + ':' + lid + ':' + rcollection
    var rkey = rcollection + ':' + rid + ':' + lcollection

    multi.zrem(lkey, rid)
    multi.zrem(rkey, lid)
    multi.exec(function (err, result) {
      if (err) { return callback(err) }
      callback(null, result)
    })
  }

  /**
   * Destroy mutual relationship (instance)
   */

  Model.prototype['remove' + ccollection] = function (robject, callback) {
    Model['remove' + ccollection](this, robject, callback)
  }

  /**
   * List by relationship
   */

  Model['listBy' + ccollection] = function (robject, options, callback) {
    if (!callback) {
      callback = options
      options = {}
    }

    var rid = (typeof robject === 'object') ? robject[runique] : robject
    options.index = rcollection + ':' + rid + ':' + lcollection

    Model.list(options, function (err, instances) {
      if (err) { return callback(err) }
      callback(null, instances)
    })
  }
}

/**
 * Post Extend
 */

RedisDocument.__postExtend = function () {
  var Model = this
  var collection = Model.collection
  var uniqueId = Model.uniqueId
  var schema = Model.schema

  // ensure a unique identifier is defined
  if (!schema[uniqueId]) {
    schema[uniqueId] = {
      type: 'string',
      required: true,
      default: Model.defaults.uuid,
      format: 'uuid'
    }
  }

  // add timestamps to schema
  var timestamp = { type: 'number', order: true, default: Model.defaults.timestamp }
  if (!schema.created) { schema.created = timestamp }
  if (!schema.modified) { schema.modified = timestamp }

  // create a placeholder for index config
  Model.__indices = []

  // Iterate through schema properties and define indices
  Object.keys(schema).forEach(function (key) {
    var property = schema[key]

    if (property.order) {
      Model.indexOrder(key)
    }

    // add a findByUnique method
    if (property.unique) {
      Model.indexUnique(key)
      var method = 'getBy' + key.charAt(0).toUpperCase() + key.slice(1)
      Model[method] = getByUnique(collection, key)
    }

    // add a findBySecondary method
    if (property.secondary) {
      Model.indexSecondary(key)
      method = 'listBy' + key.charAt(0).toUpperCase() + key.slice(1)
      Model[method] = listBySecondary(collection, key)
    }

    // add a find by referenced object method
    if (property.reference) {
      Model.indexReference(key, property.reference)
      method = 'listBy' + key.charAt(0).toUpperCase() + key.slice(1)
      Model[method] = listByReference(collection, key, property.reference)
    }
  })
}

/**
 * Return a method to find documents by unique index
 */

function getByUnique (collection, key) {
  var index = collection + ':' + key

  return function (value, options, callback) {
    var Model = this
    var client = Model.__client

    if (!callback) {
      callback = options
      options = {}
    }

    client.hget(index, value, function (err, id) {
      if (err) { return callback(err) }

      Model.get(id, options, function (err, instance) {
        if (err) { return callback(err) }
        callback(null, instance)
      })
    })
  }
}

/**
 * Return a method to find documents by secondary index
 */

function listBySecondary (collection, key) {
  return function (value, options, callback) {
    var Model = this
    var index = collection + ':' + key + ':' + value

    if (!callback) {
      callback = options
      options = {}
    }

    options.index = index

    Model.list(options, function (err, instances) {
      if (err) { return callback(err) }
      callback(null, instances)
    })
  }
}

function listByReference (collection, key, reference) {
  return function (referenceId, options, callback) {
    var Model = this

    if (!callback) {
      callback = options
      options = {}
    }

    var index = reference.collection
    index += ':'
    index += referenceId
    index += ':'
    index += collection

    options.index = index

    Model.list(options, function (err, instances) {
      if (err) { return callback(err) }
      callback(null, instances)
    })
  }
}

/**
 * List newest
 */

RedisDocument.listNewest = function (options, callback) {
  var Model = this

  if (!callback) {
    callback = options
    options = {}
  }

  options.index = Model.collection + ':created'

  Model.list(options, function (err, instances) {
    if (err) { return callback(err) }
    callback(null, instances)
  })
}

/**
 * List earliest
 */

RedisDocument.listEarliest = function (options, callback) {
  var Model = this

  if (!callback) {
    callback = options
    options = {}
  }

  options.index = Model.collection + ':created'
  options.order = 'normal'

  Model.list(options, function (err, instances) {
    if (err) { return callback(err) }
    callback(null, instances)
  })
}

/**
 * Exports
 */

module.exports = RedisDocument
