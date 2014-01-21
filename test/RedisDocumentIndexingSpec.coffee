# Test dependencies
cwd       = process.cwd()
path      = require 'path'
Faker     = require 'Faker'
chai      = require 'chai'
sinon     = require 'sinon'
sinonChai = require 'sinon-chai'
expect    = chai.expect




# Configure Chai and Sinon
chai.use sinonChai
chai.should()




# Code under test
Modinha       = require 'modinha'
RedisDocument = require path.join(cwd, 'lib/RedisDocument')




# Redis lib for spying and stubbing
redis   = require 'redis'
client  = redis.createClient()
multi   = redis.Multi.prototype
rclient = redis.RedisClient.prototype




describe 'Indexing', ->


  {Document,data,documents,jsonDocuments} = {}
  {err,instance,instances,update,deleted,original,ids} = {}


  before ->
    schema =
      unique:    { type: 'string' }
      reference: { type: 'string' }
      secondary: { type: 'string' }


    Document = Modinha.define 'documents', schema
    Document.extend RedisDocument

    Document.indexSet
      params: '_id'
      key: 'whatever:$:youwant'
      value: 'indexed'



    # lookup object by some 1:1 attribute
    Document.defineIndex
      type:  'hash'
      key:   'documents:unique'
      field: 'unique'
      value: '_id'

    # has many/belongs to/has many through
    Document.defineIndex
      type:  'sorted'
      key:    ['references:$:documents', 'reference']
      score:  'created'
      member: '_id'

    # find objects by 1:* attributes
    Document.defineIndex
      type:   'sorted'
      key:    ['documents:#:$', 'secondary', 'secondary']
      score:  'created'
      member: '_id'



    Document.__redis = redis
    Document.__client = client

    # Mock data
    data = []

    for i in [0..9]
      data.push
        unique:    Faker.random.number(1000).toString()
        reference: Faker.random.number(1000).toString()
        secondary: Faker.random.number(1000).toString()

    documents = Document.initialize(data, { private: true })
    jsonDocuments = documents.map (d) ->
      Document.serialize(d)
    ids = documents.map (d) ->
      d._id




  describe 'index', ->

    before ->
      m = client.multi()
      instance = documents[0]
      sinon.spy multi, 'hset'
      sinon.spy multi, 'zadd'
      Document.index2 m, instance

    after ->
      multi.hset.restore()
      multi.zadd.restore()

    it 'should index an object by unique values', ->
      multi.hset.should.have.been.calledWith 'documents:unique', instance.unique, instance._id

    it 'should index an object by descriptive values', ->
      multi.zadd.should.have.been.calledWith "documents:secondary:#{instance.secondary}", instance.created, instance._id

    #it 'should index an object by multiple values'

    #it 'should index an object by creation time', ->
    #  multi.zadd.should.have.been.calledWith 'documents:created', instance.created, instance._id

    #it 'should index an object by modification time', ->
    #  multi.zadd.should.have.been.calledWith 'documents:modified', instance.modified, instance._id

    #it 'should index an object by reference', ->
    #  multi.zadd.should.have.been.calledWith "references:#{instance.reference}:documents", instance.created, instance._id

    #it 'should index an object by set', ->
    #  multi.zadd.should.have.been.calledWith "whatever:#{instance._id}:youwant", instance.created, instance.indexed




  #describe 'deindex', ->

  #  before ->
  #    m = client.multi()
  #    instance = documents[0]
  #    sinon.spy multi, 'hdel'
  #    sinon.spy multi, 'zrem'
  #    Document.deindex m, instance

  #  after ->
  #    multi.hdel.restore()
  #    multi.zrem.restore()

  #  it 'should remove an object from unique index', ->
  #    multi.hdel.should.have.been.calledWith 'documents:unique', instance.unique

  #  it 'should remove an object from secondary index', ->
  #    multi.zrem.should.have.been.calledWith "documents:secondary:#{instance.secondary}", instance._id

  #  it 'should remove an object from created index', ->
  #    multi.zrem.should.have.been.calledWith 'documents:created', instance._id

  #  it 'should remove an object from modified index', ->
  #    multi.zrem.should.have.been.calledWith 'documents:modified', instance._id

  #  it 'should remove an object from a referenced object index', ->
  #    multi.zrem.should.have.been.calledWith "references:#{instance.reference}:documents", instance._id

  #  it 'should remove an object from a set index', ->
  #    multi.zrem.should.have.been.calledWith "whatever:#{instance._id}:youwant", instance.indexed



  #describe 'reindex', ->

  #  beforeEach ->
  #    sinon.spy multi, 'hset'
  #    sinon.spy multi, 'zadd'
  #    sinon.spy multi, 'hdel'
  #    sinon.spy multi, 'zrem'

  #  afterEach ->
  #    multi.hset.restore()
  #    multi.zadd.restore()
  #    multi.hdel.restore()
  #    multi.zrem.restore()


  #  describe 'with changed unique value', ->

  #    beforeEach ->
  #      m = client.multi()
  #      Document.reindex m, { _id: 'id', unique: 'updated' }, { _id: 'id', unique: 'original' }

  #    it 'should index the object id by new value', ->
  #      multi.hset.should.have.been.calledWith 'documents:unique', 'updated', 'id'

  #    it 'should deindex the object id by old value', ->
  #      multi.hdel.should.have.been.calledWith 'documents:unique', 'original'


  #  describe 'with unchanged unique value', ->

  #    beforeEach ->
  #      m = client.multi()
  #      Document.reindex m, { _id: 'id', unique: 'original' }, { _id: 'id', unique: 'original' }

  #    it 'should not reindex the value', ->
  #      multi.hset.should.not.have.been.called
  #      multi.hdel.should.not.have.been.called


  #  describe 'with changed secondary value', ->

  #    beforeEach ->
  #      m = client.multi()

  #      instance =
  #        _id: 'id'
  #        secondary: 'updated'
  #        modified: '1235'
  #      original =
  #        _id: 'id'
  #        secondary: 'original'
  #        modified: '1234'

  #      Document.reindex m, instance, original

  #    it 'should index the object id by new value', ->
  #      multi.zadd.should.have.been
  #        .calledWith 'documents:secondary:updated', instance.modified, instance._id

  #    it 'should deindex the object id by old value', ->
  #      multi.zrem.should.have.been
  #        .calledWith 'documents:secondary:original', instance._id


  #  describe 'with unchanged secondary value', ->

  #    beforeEach ->
  #      m = client.multi()

  #      instance =
  #        _id: 'id'
  #        secondary: 'updated'
  #        modified: '1234'

  #      Document.reindex m, instance, instance

  #    it 'should not reindex the value', ->
  #      multi.zadd.should.not.have.been.called
  #      multi.zrem.should.not.have.been.called


  #  describe 'with changed ordered value', ->

  #    beforeEach ->
  #      m = client.multi()

  #      instance =
  #        _id: 'id'
  #        modified: '1235'
  #      original =
  #        _id: 'id'
  #        modified: '1234'

  #      Document.reindex m, instance, original

  #    it 'should reindex the object id with a new score', ->
  #      multi.zadd.should.have.been.calledWith 'documents:modified', instance.modified, instance._id


  #  describe 'with unchanged ordered value', ->

  #    beforeEach ->
  #      m = client.multi()

  #      instance =
  #        _id: 'id'
  #        modified: '1234'

  #      Document.reindex m, instance, instance

  #    it 'should not reindex the object id with a new score', ->
  #      multi.zadd.should.not.have.been.called


  #  describe 'with changed reference value', ->

  #    beforeEach ->
  #      m = client.multi()

  #      instance =
  #        _id: 'id'
  #        reference: '1235'
  #        created: '3456'
  #      original =
  #        _id: 'id'
  #        reference: '1234'

  #      Document.reindex m, instance, original

  #    it 'should index the object id by new reference', ->
  #      multi.zadd.should.have.been.calledWith "references:#{instance.reference}:documents", instance.created, instance._id

  #    it 'should deindex the object id by old reference', ->
  #      multi.zrem.should.have.been.calledWith "references:#{original.reference}:documents", instance._id


  #  describe 'with unchanged reference value', ->

  #    beforeEach ->
  #      m = client.multi()

  #      instance =
  #        _id: 'id'
  #        reference: '1235'

  #      Document.reindex m, instance, instance

  #    it 'should not reindex the object id by reference', ->
  #      multi.zadd.should.not.have.been.called
  #      multi.zrem.should.not.have.been.called


  #  describe 'set', ->

  #    beforeEach ->
  #      m = client.multi()

  #      instance =
  #        _id: 'id'
  #        indexed: '1235'
  #        created: '3456'
  #      original =
  #        _id: 'id'
  #        indexed: '1234'

  #      Document.reindex m, instance, original

  #    it 'should remove old value', ->
  #      multi.zrem.should.have.been.calledWith "whatever:#{instance._id}:youwant", original.indexed

  #    it 'should add new value', ->
  #      multi.zadd.should.have.been.calledWith "whatever:#{instance._id}:youwant", instance.created, instance.indexed







  describe 'index value by set', ->

    it 'should register an index', ->
      config = {}
      Document.indexSet config
      Document.__indices.should.contain config



  describe 'index definition', ->

    it 'should register an index', ->
      config = {}
      Document.defineIndex config
      Document.__indices.should.contain config


  describe 'indexing by hash', ->

    it 'should store a one to one reference', ->
      Document.defineIndex
        type: 'hash'
        hash: 'documents:uniqueLookup'
        key: 'unique'
        value: '_id'


  describe 'indexing by sorted set', ->


