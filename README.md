The RedisDocument mixin for [Modinha](https://github.com/christiansmith/Modinha) defines a collection of persistence methods that map cleanly between HTTP semantics and Redis data structures. 

### Usage

Suppose we've defined an Account model with Modinha like so:

'''javascript
var Modinha = require('modinha')
  , RedisDocument = require('modinha-redis').RedisDocument

var Account = Modinha.define('accounts', {
  email: { type: 'string', required: true, unique: true },
  role:  { type: 'string', secondary: true, enum: ['admin', 'editor', 'author'] },
  hash:  { type: 'string', private: true }
});

Account.extend(RedisDocument);
'''

RedisDocument will add the following persistence methods to the Account document.

'''
HTTP                     MODEL METHOD

GET    /accounts         Account.list(options, callback)
GET    /accounts/id      Account.get(ids, options, callback)
POST   /accounts         Account.insert(data, options, callback)
PUT    /accounts/id      Account.put(id, data, options, callback)
PATCH  /accounts/id      Account.patch(id, data, options, callback)
DELETE /accounts/id      Account.delete(id, callback)
'''

Extending Account with RedisDocument will also define the following properties on Account.schema:

'''javascript
_id:      { type: 'string', required: true, default: Model.defaults.uuid },
created:  { type: 'number', order: true, default: Model.defaults.timestamp },
modified: { type: 'number', order: true, default: Model.defaults.timestamp }
'''

Since we defined `unique` and `secondary` properties on email and role, respectively, the mixin will also generate property specific methods for those indexes.

'''javascript
Account.getByEmail(email, callback)
Account.listByRole(role, callback)
'''

### More about indexing

Unique values are enforced by the `insert`, `put`, and `patch` methods. If you write custom methods, you can use Account.enforceUnique(callback) to generate a UniqueValueError.

The default timestamp methods define an ordered index for created and modified. Account.list(options, callback) uses the `accounts:created` index by default to deliver reverse chronological account listings.

...

