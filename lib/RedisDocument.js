/**
 * Module dependencies
 */

var util = require('util')
  , async  = require('async')
  , redis  = require('redis')
  , client = redis.createClient()
  ;


/**
 * Constructor mixin
 */

function RedisDocument () {}


/**
 * List
 */

RedisDocument.list = function (options, callback) {
  var Model      = this
    , collection = Model.collection
    ;

  // optional options argument
  if (!callback) {
    callback = options;
    options = {};
  }

  // assign the default index if none is provided 
  var index = options.index || collection + ':created';

  // default page and size
  var page = options.page || 1
    , size = parseInt(options.size) || 50
    ;

  // calculate start and end index
  // for the sorted set range lookup
  var startIndex = (size * (page - 1))
    , endIndex   = (startIndex + size) - 1;    
    ;

  // get a range of ids from the index
  client.zrevrange(index, startIndex, endIndex, function (err, ids) {
    if (err) { return callback(err); }

    // handle empty results
    if (!ids || ids.length === 0) { 
      return callback(null, []); 
    } 

    // get by id
    Model.get(ids, options, function (err, instances) {
      if (err) { return callback(err); }
      callback(null, instances);
    });
  });
};


/**
 * Get
 */

RedisDocument.get = function (ids, options, callback) {
  var Model = this
    , collection = Model.collection
    ;

  // optional options argument
  if (!callback) {
    callback = options;
    options = {};
  }

  // return an object instead of an array
  // if the first argument is a string
  if (typeof ids === 'string') { 
    options.first = true;
  }

  // don't call hmget with undefined ids
  if (!ids) { 
    return callback(null, null); 
  }

  // don't call hmget with an empty array
  if (Array.isArray(ids) && ids.length === 0) {
    return callback(null, [])
  }

  // if redis responds with undefined or null
  // values, initialization should provide null
  // instead of an instance
  options.nullify = true;

  // send redis the hash multiget command
  client.hmget(collection, ids, function (err, result) {
    if (err) { return callback(err); }
    callback(null, Model.initialize(result, options));
  });
};


/**
 * Insert
 */

RedisDocument.insert = function (data, options, callback) {
  var Model       = this
    , schema      = Model.schema
    , collection  = Model.collection
    , uniqueId    = Model.uniqueId
    , instance    = Model.initialize(data, { private: true })
    , validation  = instance.validate()
    ;

  // optional options
  if (!callback) {
    callback = options;
    options = {};
  }

  // handle invalid data
  if (!validation.valid) { return callback(validation); }

  Model.enforceUnique(instance, function (err) {
    if (err) { return callback(err); }

    // batch operations
    var multi = client.multi();

    // store the instance
    multi.hset(collection, instance[uniqueId], Model.serialize(instance));

    // index the instance
    Model.index(multi, instance);

    // execute the set of ops
    multi.exec(function (err, result) {
      if (err) { return callback(err); }
      callback(null, Model.initialize(instance, options));
    });
  });
};


/**
 * Put
 */

RedisDocument.put = function (id, data, options, callback) {
  var Model       = this
    , schema      = Model.schema
    , collection  = Model.collection
    , uniqueId    = Model.uniqueId
    , instance    = Model.initialize(data, { private: true }) // ?? private ??
    , validation  = instance.validate()
    ;

  // optional options
  if (!callback) {
    callback = options;
    options = {};
  }

  // handle invalid data
  if (!validation.valid) { return callback(validation); }

  // Get the existing instance so we can reindex
  Model.get(id, function (err, original) {
    if (err) { return callback(err); }

    // not found?

    Model.enforceUnique(instance, function (err) {
      if (err) { return callback(err); }

      // batch operations
      var multi = client.multi();

      // store the instance
      multi.hset(collection, instance[uniqueId], Model.serialize(instance));

      // index the instance
      Model.reindex(multi, instance, original);

      // execute the set of ops
      multi.exec(function (err, result) {
        if (err) { return callback(err); }
        callback(null, Model.initialize(instance, options));
      });   
    });
  });
};


/**
 * Patch
 */

RedisDocument.patch = function (id, data, options, callback) {
  var Model = this
    , collection = Model.collection
    , uniqueId   = Model.uniqueId
    ;

  // optional options
  if (!callback) {
    callback = options;
    options = {};
  }

  // get the existing data
  Model.get(id, { private:true }, function (err, instance) {
    if (err) { return callback(err); }
    
    // not found?
    
    // copy the original (for reindexing)
    var original = Model.initialize(instance, { private: true });

    // merge the new values into the instance
    instance.merge(data);

    // validate the mutated instance
    var validation = instance.validate();
    if (!validation.valid) { return callback(validation); }

    Model.enforceUnique(instance, function (err) {
      if (err) { return callback(err); }

      // batch operations
      var multi = client.multi();

      // store the instance
      multi.hset(collection, instance[uniqueId], Model.serialize(instance));

      // index the instance
      Model.reindex(multi, instance, original);

      // execute the set of ops
      multi.exec(function (err, result) {
        if (err) { return callback(err); }
        callback(null, Model.initialize(instance, options));
      });
    });
  });
};


/**
 * Delete
 */

RedisDocument.delete = function (id, callback) {
  var Model = this;

  // Get the object so that it can be deindexed
  Model.get(id, { private: true }, function (err, result) {
    if (err) { return callback(err); }

    // not found?

    // batch operations
    var multi = client.multi();

    // remove the instance(s)
    multi.hdel(Model.collection, id);

    // leave no trace in the indexes
    if (!Array.isArray(result)) { result = [result]; }
    result.forEach(function (instance) {
      Model.deindex(multi, instance);
    });

    // execute the set of ops
    multi.exec(function (err) {
      if (err) { callback(err); }
      callback(null, true);
    });
  });
};


/**
 * Index
 *
 * Takes a redis multi object and a model instance.
 * Iterate through the schema (does not currently
 * support nested properties) and add appropriate 
 * indexing operations to the batch, if any.
 */

RedisDocument.index = function (multi, data) {
  var Model      = this
    , collection = Model.collection
    , uniqueId   = Model.uniqueId
    , schema     = Model.schema
    , id         = data[uniqueId]
    ;

  Object.keys(schema).forEach(function (key) {
    var property = schema[key]
      , value    = data[key]
      , index
      , score
      ;

    // NOTE: 
    // Append (+=) is an order of magnitude
    // faster than string concatentation (+).
    // http://jsperf.com/append-string-vs-join-array

    // Unique index
    if (property.unique && value) {
      index = collection;
      index += ':';
      index += key;
      multi.hset(index, value, id);
    }

    // Secondary index
    if (property.secondary && value) {
      index = collection;
      index += ':';
      index += key;
      index += ':';
      index += value;
      score = data.modified;
      multi.zadd(index, score, id);
    }

    // Ordered index
    if (property.order && value) {
      index = collection;
      index += ':';
      index += key;
      // If order is true, assume that value is a score.
      // Otherwise, treat the value of order as a property 
      // name to use for a score.
      score = (property.order === true) 
               ? value 
               : data[property.order];      
      multi.zadd(index, score, id);
    }

    // Object reference index
    if (property.reference && value) {
      index = property.reference.collection
      index += ':';
      index += value;
      index += ':';
      index += collection;
      score = data.created;
      multi.zadd(index, score, id);
    }
  });
};


/**
 * Deindex
 *
 * Takes a redis multi object and an instance.
 * Reverse of RedisDocument.index().
 */

RedisDocument.deindex = function (multi, data) {
  var Model      = this
    , collection = Model.collection
    , uniqueId   = Model.uniqueId
    , schema     = Model.schema
    , id         = data[uniqueId]
    ;

  Object.keys(schema).forEach(function (key) {
    var property = schema[key]
      , value    = data[key]
      , index
      ;

    // Unique index
    if (property.unique && value) {
      index = collection;
      index += ':';
      index += key;
      multi.hdel(index, value);
    }

    // Secondary index
    if (property.secondary && value) {
      index = collection;
      index += ':';
      index += key;
      index += ':';
      index += value;
      multi.zrem(index, id);
    }

    // Ordered index
    if (property.order && value) {
      index = collection;
      index += ':';
      index += key;
      multi.zrem(index, id);
    }

    // Object reference index
    if (property.reference && value) {
      index = property.reference.collection
      index += ':';
      index += value;
      index += ':';
      index += collection;
      multi.zrem(index, id);
    }
  });  
};


/**
 * Reindex
 */

RedisDocument.reindex = function (multi, data, orig) {
  var Model      = this
    , collection = Model.collection
    , uniqueId   = Model.uniqueId
    , schema     = Model.schema
    , id         = data[uniqueId]
    ;

  // THROW AN ERROR IF ID's DON'T MATCH?

  Object.keys(schema).forEach(function (key) {
    var property = schema[key]
      , newVal   = data[key]
      , oldVal   = orig[key]
      , index
      , score
      ;

    // check for changed values
    if (newVal !== oldVal) {
      
      // Unique index
      if (property.unique) {
        index = collection;
        index += ':';
        index += key;      
        if (oldVal) { multi.hdel(index, oldVal); }
        if (newVal) { multi.hset(index, newVal, id); }
      }

      // Secondary index
      if (property.secondary) {
        if (oldVal) {
          index = collection;
          index += ':';
          index += key;
          index += ':';
          index += oldVal;
          multi.zrem(index, id);
        }

        if (newVal) {
          index = collection;
          index += ':';
          index += key;
          index += ':';
          index += newVal;
          score = data.modified;
          multi.zadd(index, score, id);
        }
      }

      // Ordered index
      if (property.order) {
        index = collection;
        index += ':';
        index += key;
        score = newVal;
        // If order is true, assume that value is a score.
        // Otherwise, treat the value of order as a property 
        // name to use for a score.
        score = (property.order === true) 
                 ? newVal 
                 : data[property.order];   
        multi.zadd(index, score, id);
      }

      // Object reference index
      if (property.reference) {
        if (oldVal) {
          index = property.reference.collection
          index += ':';
          index += oldVal;
          index += ':';
          index += collection;
          multi.zrem(index, id);
        }

        if (newVal) {
          index = property.reference.collection
          index += ':';
          index += newVal;
          index += ':';
          index += collection;
          score = data.created;
          multi.zadd(index, score, id);        
        }
      }      
    }
  });
};


/**
 * Enforce unique values
 */

RedisDocument.enforceUnique = function (data, callback) {
  var Model  = this
    , schema = Model.schema
    , checks = []
    ;

  Object.keys(schema).forEach(function (key) {
    var property = schema[key];

    if (property && property.unique) {
      checks.push(function (done) {
        var method = 'getBy' + key.charAt(0).toUpperCase() + key.slice(1);
        Model[method](data[key], function (err, instance) {
          if (err)      { return done(err); }
          if (instance) { return done(new UniqueValueError(key)); }
          done(null);
        });
      }); 
    }
  });

  async.parallel(checks, function (err) {
    if (err) { return callback(err); }
    callback(null);
  });
};


/**
 * RegisteredEmailError
 */

function UniqueValueError(property) {
  this.name = 'UniqueValueError';
  this.message = property + ' must be unique';
  this.statusCode = 400;
  Error.call(this, this.message);
  Error.captureStackTrace(this, arguments.callee);
}

util.inherits(UniqueValueError, Error);
RedisDocument.UniqueValueError = UniqueValueError;


/**
 * Post Extend
 */

RedisDocument.__postExtend = function () {
  var Model      = this
    , collection = Model.collection
    , uniqueId   = Model.uniqueId
    , schema     = Model.schema
    ;

  Object.keys(schema).forEach(function (key) {
    var property = schema[key];

    // add a findByUnique method
    if (property.unique) {
      var method = 'getBy' + key.charAt(0).toUpperCase() + key.slice(1);
      Model[method] = getByUnique(collection, key);
    }

    // add a findBySecondary method
    if (property.secondary) {
      var method = 'listBy' + key.charAt(0).toUpperCase() + key.slice(1);
      Model[method] = listBySecondary(collection, key);
    }

    // ...

  });

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
  if (!schema.created)  { schema.created  = timestamp; }
  if (!schema.modified) { schema.modified = timestamp; }
};


/**
 * Return a method to find documents by unique index
 */

function getByUnique (collection, key) {
  var index = collection + ':' + key;

  return function (value, options, callback) {
    var Model = this;

    if (!callback) {
      callback = options;
      options = {};
    }

    client.hget(index, value, function (err, id) {
      if (err) { return callback(err); }
    
      Model.get(id, options, function (err, instance) {
        if (err) { return callback(err); }
        callback(null, instance);
      });
    });
  };
};


/**
 * Return a method to find documents by secondary index
 */

function listBySecondary (collection, key) {
  return function (value, callback) {
    var Model = this
      , index = collection + ':' + key + ':' + value
      ;

    Model.list({ index: index }, function (err, instances) {
      if (err) { return callback(err); }
      callback(null, instances);
    });
  };
};


/**
 * Exports
 */

module.exports = RedisDocument;
