# Test dependencies
cwd       = process.cwd()
path      = require 'path'
Faker     = require 'faker'
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
      deleted:   { type: 'string', unique: true }
      reference: { type: 'string' }
      secondary: { type: 'string' }
      nested:    { type: 'object' }
      flag:      { type: 'string' }


    Document = Modinha.define 'documents', schema
    Document.extend RedisDocument


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
      score:  'modified'
      member: '_id'

    # compound field name
    Document.defineIndex
      type:  'hash'
      key:   'a:b:c'
      field: ['$:$', 'reference', 'secondary']
      value: '_id'

    # nested property
    Document.defineIndex
      type:  'hash'
      key:   ['documents:$', 'nested.key']
      field: ['$', 'nested.prop']
      value: '_id'

    # dynamic nested property
    Document.defineIndex
      type:  'hash'
      key:   'dynamic:field'
      field: ['$', ['nested.$', 'flag']]
      value: '_id'

    Document.__redis = redis
    Document.__client = client

    # Mock data
    data = []

    for i in [0..9]
      data.push
        unique:    Faker.random.number(1000).toString()
        reference: Faker.random.number(1000).toString()
        secondary: Faker.random.number(1000).toString()
        nested:
          key:  'value'
          prop: Faker.random.number(1000).toString()
          foo:  'bar'
        flag: 'foo'


    documents = Document.initialize(data, { private: true })
    jsonDocuments = documents.map (d) ->
      Document.serialize(d)
    ids = documents.map (d) ->
      d._id




  describe 'key interpolation', ->

    it 'should replace # with literal parameters', ->
      Document.indexKey(['a:#:b:#:c:#:d:#', '1', '2', '3', '4'])
        .should.equal 'a:1:b:2:c:3:d:4'

    it 'should replace $ with object values', ->
      data = { a: 1, b: 2, c: '3', d: '4' }
      Document.indexKey(['a:$:b:$:c:$:d:$', 'a', 'b', 'c', 'd'], data)
        .should.equal 'a:1:b:2:c:3:d:4'

    it 'should replace # and $ with the correct params', ->
      data = { alpha: 1, bravo: 2, charlie: '3', delta: '4' }
      Document.indexKey([
        'a:#:b:$:c:#:d:$'
        'alpha'
        'bravo'
        'charlie'
        'delta'
      ], data).should.equal 'a:alpha:b:2:c:charlie:d:4'

    it 'should evaluate array params', ->
      data = { a: 1, b: { c: 'd', d: { e: 5 } } }
      Document.indexKey([
        'answer:$'
        ['b.$.e', 'b.c']
      ], data).should.equal 'answer:5'




  describe 'index', ->

    before ->
      m = client.multi()
      instance = documents[0]
      sinon.stub multi, 'hset'
      sinon.stub multi, 'zadd'
      sinon.stub(multi, 'exec').callsArgWith(0, null, [])
      Document.index m, instance

    after ->
      multi.hset.restore()
      multi.zadd.restore()
      multi.exec.restore()

    it 'should add a field to a hash', ->
      multi.hset.should.have.been.calledWith 'documents:unique', instance.unique, instance._id

    it 'should add a dynamically named field to a hash', ->
      multi.hset.should.have.been.calledWith 'a:b:c', "#{instance.reference}:#{instance.secondary}", instance._id

    it 'should add a "nested property" field to a hash', ->
      multi.hset.should.have.been.calledWith 'documents:value', instance.nested.prop, instance._id

    it 'should add a "dynamic property" field to a hash', ->
      multi.hset.should.have.been.calledWith 'dynamic:field', 'bar', instance._id

    it 'should add a member to a sorted set', ->
      multi.zadd.should.have.been.calledWith "documents:secondary:#{instance.secondary}", sinon.match.number, instance._id




  describe 'deindex', ->

    before ->
      m = client.multi()
      instance = documents[0]
      sinon.stub multi, 'hdel'
      sinon.stub multi, 'zrem'
      sinon.stub(multi, 'exec').callsArgWith(0, null, [])
      Document.deindex m, instance

    after ->
      multi.hdel.restore()
      multi.zrem.restore()
      multi.exec.restore()

    it 'should remove a field from a hash', ->
      multi.hdel.should.have.been.calledWith 'documents:unique', instance.unique

    it 'should remove a dynamically named field from a hash', ->
      multi.hdel.should.have.been.calledWith 'a:b:c', "#{instance.reference}:#{instance.secondary}"

    it 'should remove a "nested property" field from a hash', ->
      multi.hdel.should.have.been.calledWith 'documents:value', instance.nested.prop

    it 'should remove a "dynamic property" field from a hash', ->
      multi.hdel.should.have.been.calledWith 'dynamic:field', 'bar'

    it 'should remove a member from a sorted set', ->
      multi.zrem.should.have.been.calledWith "documents:secondary:#{instance.secondary}", instance._id




  describe 'reindex', ->

    beforeEach ->
      sinon.stub multi, 'hset'
      sinon.stub multi, 'zadd'
      sinon.stub multi, 'hdel'
      sinon.stub multi, 'zrem'
      sinon.stub(multi, 'exec').callsArgWith(0, null, [])

    afterEach ->
      multi.hset.restore()
      multi.zadd.restore()
      multi.hdel.restore()
      multi.zrem.restore()
      multi.exec.restore()


    describe 'with changed value indexed by hash', ->

      beforeEach ->
        m = client.multi()
        Document.reindex m, { _id: 'id', unique: 'updated' }, { _id: 'id', unique: 'original', deleted: 'not deleted' }

      it 'should index the object by new value', ->
        multi.hset.should.have.been.calledWith 'documents:unique', 'updated', 'id'

      it 'should deindex the object by old value', ->
        multi.hdel.should.have.been.calledWith 'documents:unique', 'original'

      it 'should deindex the object by a deleted property', ->
        multi.hdel.should.have.been.calledWith 'documents:deleted', 'not deleted'
        multi.hset.should.not.have.been.calledWith 'documents:deleted'


    describe 'with change to hash index with dynamically named field', ->

      beforeEach ->
        m = client.multi()
        Document.reindex m, { _id: 'id', reference: '345', secondary: '678' }, { _id: 'id', reference: '123', secondary: '456' }

      it 'should index the modified version of the instance', ->
        multi.hset.should.have.been.calledWith 'a:b:c', '345:678', 'id'

      it 'should deindex the original version of the instance', ->
        multi.hdel.should.have.been.calledWith 'a:b:c', '123:456'


    describe 'with unchanged value indexed by hash', ->

      beforeEach ->
        m = client.multi()
        Document.reindex m, { _id: 'id', unique: 'original' }, { _id: 'id', unique: 'original' }

      it 'should not reindex', ->
        multi.hset.should.not.have.been.called
        multi.hdel.should.not.have.been.called


    describe 'with changed value indexed by sorted set', ->

      beforeEach ->
        m = client.multi()

        instance =
          _id: 'id'
          secondary: 'updated'
          modified: '1235'
        original =
          _id: 'id'
          secondary: 'original'
          modified: '1234'

        Document.reindex m, instance, original

      it 'should index the object by new value', ->
        multi.zadd.should.have.been
          .calledWith 'documents:secondary:updated', instance.modified, instance._id

      it 'should deindex the object by old value', ->
        multi.zrem.should.have.been
          .calledWith 'documents:secondary:original', instance._id


    describe 'with unchanged value indexed by sorted set', ->

      beforeEach ->
        m = client.multi()

        instance =
          _id: 'id'
          secondary: 'updated'
          modified: '1234'

        Document.reindex m, instance, instance

      it 'should not reindex the value', ->
        multi.zadd.should.not.have.been.called
        multi.zrem.should.not.have.been.called




  describe 'explicit index definition', ->

    it 'should register an index', ->
      config = {}
      Document.defineIndex config
      Document.__indices.should.contain config


  describe 'unique index definition', ->

    it 'should register a unique index', ->
      Document.indexUnique('unique')
      index = Document.__indices[..].pop()
      index.type.should.equal  'hash'
      index.key.should.equal   'documents:unique'
      index.field.should.equal 'unique'
      index.value.should.equal '_id'


  describe 'secondary index definition', ->

    it 'should register a secondary index', ->
      Document.indexSecondary('secondary')
      index = Document.__indices[..].pop()
      index.type.should.equal   'sorted'
      index.key[0].should.equal 'documents:#:$'
      index.key[1].should.equal 'secondary'
      index.key[2].should.equal 'secondary'
      index.score.should.equal  'modified'
      index.member.should.equal '_id'


  describe 'reference index definition', ->

    it 'should register a reference index', ->
      Document.indexReference('reference', { collection: 'references' })
      index = Document.__indices[..].pop()
      index.type.should.equal   'sorted'
      index.key[0].should.equal 'references:$:documents'
      index.key[1].should.equal 'reference'
      index.score.should.equal  'created'
      index.member.should.equal '_id'


  describe 'order index definition', ->

    it 'should register an order index', ->
      Document.indexOrder('created')
      index = Document.__indices[..].pop()
      index.type.should.equal   'sorted'
      index.key[0].should.equal 'documents:created'
      index.score.should.equal  'created'
      index.member.should.equal '_id'
