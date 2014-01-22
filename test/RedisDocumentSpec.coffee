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




describe 'RedisDocument', ->


  {Document,data,documents,jsonDocuments} = {}
  {err,instance,instances,update,deleted,original,ids} = {}


  before ->
    schema =
      description: { type: 'string', required:  true }
      unique:      { type: 'string', unique:    true }
      secret:      { type: 'string', private:   true }
      secondary:   { type: 'string', secondary: true }
      reference:   { type: 'string', reference: { collection: 'references' } }


    Document = Modinha.define 'documents', schema
    Document.extend RedisDocument


    Document.__redis = redis
    Document.__client = client

    # Mock data
    data = []

    for i in [0..9]
      data.push
        description: Faker.Lorem.words(5).join(' ')
        unique: Faker.random.number(1000).toString()
        secondary: Faker.random.number(1000).toString()
        reference: Faker.random.number(1000).toString()
        indexed: Faker.random.number(1000).toString()
        secret: 'nobody knows'

    documents = Document.initialize(data, { private: true })
    jsonDocuments = documents.map (d) ->
      Document.serialize(d)
    ids = documents.map (d) ->
      d._id




  describe 'schema', ->

    it 'should have unique identifier', ->
      Document.schema[Document.uniqueId].should.be.an.object

    it 'should have "created" timestamp', ->
      Document.schema.created.default.should.equal Modinha.defaults.timestamp

    it 'should have "modified" timestamp', ->
      Document.schema.modified.default.should.equal Modinha.defaults.timestamp




  describe 'list', ->

    describe 'by default', ->

      before (done) ->
        sinon.spy rclient, 'zrevrange'
        sinon.stub(rclient, 'hmget').callsArgWith 2, null, jsonDocuments
        Document.list (error, results) ->
          err = error
          instances = results
          done()

      after ->
        rclient.hmget.restore()
        rclient.zrevrange.restore()

      it 'should query the created index', ->
        rclient.zrevrange.should.have.been.calledWith 'documents:created', 0, 49

      it 'should provide null error', ->
        expect(err).to.be.null

      it 'should provide a list of instances', ->
        instances.length.should.equal 10
        instances.forEach (instance) ->
          expect(instance).to.be.instanceof Document

      it 'should not initialize private properties', ->
        instances.forEach (instance) ->
          expect(instance.secret).to.be.undefined

      it 'should provide the list in reverse chronological order', ->
        rclient.zrevrange.should.have.been.called


    describe 'by index', ->

      before (done) ->
        sinon.stub(rclient, 'zrevrange').callsArgWith 3, null, ids
        sinon.stub(rclient, 'hmget').callsArgWith 2, null, jsonDocuments
        Document.list { index: 'documents:secondary:value' }, (error, results) ->
          err = error
          instances = results
          done()

      after ->
        rclient.hmget.restore()
        rclient.zrevrange.restore()

      it 'should query the provided index', ->
        rclient.zrevrange.should.have.been.calledWith 'documents:secondary:value'

      it 'should provide null error', ->
        expect(err).to.be.null

      it 'should provide a list of instances', ->
        instances.length.should.equal 10
        instances.forEach (instance) ->
          expect(instance).to.be.instanceof Document

      it 'should not initialize private properties', ->
        instances.forEach (instance) ->
          expect(instance.secret).to.be.undefined


    describe 'with paging', ->

      before (done) ->
        sinon.spy rclient, 'zrevrange'
        sinon.stub(rclient, 'hmget').callsArgWith 2, null, jsonDocuments
        Document.list { page: 2, size: 3 }, (error, results) ->
          err = error
          instances = results
          done()

      after ->
        rclient.hmget.restore()
        rclient.zrevrange.restore()

      it 'should retrieve a range of values', ->
        rclient.zrevrange.should.have.been.calledWith 'documents:created', 3, 5

      it 'should provide null error', ->
        expect(err).to.be.null

      it 'should provide a list of instances', ->
        instances.length.should.equal 10
        instances.forEach (instance) ->
          expect(instance).to.be.instanceof Document


    describe 'with no results', ->

      before (done) ->
        sinon.stub(rclient, 'zrevrange').callsArgWith(3, null, [])
        Document.list { page: 2, size: 3 }, (error, results) ->
          err = error
          instances = results
          done()

      after ->
        rclient.zrevrange.restore()

      it 'should provide null error', ->
        expect(err).to.be.null

      it 'should provide an empty list', ->
        Array.isArray(instances).should.be.true
        instances.length.should.equal 0


    describe 'with selection', ->

      before (done) ->
        sinon.spy rclient, 'zrevrange'
        sinon.stub(rclient, 'hmget').callsArgWith 2, null, jsonDocuments
        Document.list { select: [ 'description', 'secret' ] }, (error, results) ->
          err = error
          instances = results
          done()

      after ->
        rclient.hmget.restore()
        rclient.zrevrange.restore()

      it 'should provide null error', ->
        expect(err).to.be.null

      it 'should provide a list of instances', ->
        instances.length.should.equal 10
        instances.forEach (instance) ->
          expect(instance).to.be.instanceof Document

      it 'should only initialize selected properties', ->
        instances.forEach (instance) ->
          expect(instance._id).to.be.undefined
          instance.description.should.be.a.string

      it 'should initialize private properties if selected', ->
        instances.forEach (instance) ->
          instance.secret.should.be.a.string


    describe 'with private option', ->

      before (done) ->
        sinon.spy rclient, 'zrevrange'
        sinon.stub(rclient, 'hmget').callsArgWith 2, null, jsonDocuments
        Document.list { private: true }, (error, results) ->
          err = error
          instances = results
          done()

      after ->
        rclient.hmget.restore()
        rclient.zrevrange.restore()

      it 'should provide null error', ->
        expect(err).to.be.null

      it 'should provide a list of instances', ->
        instances.length.should.equal 10
        instances.forEach (instance) ->
          expect(instance).to.be.instanceof Document

      it 'should intialize private properties', ->
        instances.forEach (instance) ->
          instance.secret.should.equal 'nobody knows'


    describe 'in chronological order', ->

      before (done) ->
        sinon.spy rclient, 'zrange'
        sinon.stub(rclient, 'hmget').callsArgWith 2, null, jsonDocuments
        Document.list { order: 'normal' }, (error, results) ->
          err = error
          instances = results
          done()

      after ->
        rclient.hmget.restore()
        rclient.zrange.restore()

      it 'should query the created index', ->
        rclient.zrange.should.have.been.calledWith 'documents:created', 0, 49

      it 'should provide null error', ->
        expect(err).to.be.null

      it 'should provide a list of instances', ->
        instances.length.should.equal 10
        instances.forEach (instance) ->
          expect(instance).to.be.instanceof Document

      it 'should not initialize private properties', ->
        instances.forEach (instance) ->
          expect(instance.secret).to.be.undefined

      it 'should provide the list in chronological order', ->
        rclient.zrange.should.have.been.called




  describe 'get', ->

    describe 'by string', ->

      before (done) ->
        document = documents[0]
        json = jsonDocuments[0]
        sinon.stub(rclient, 'hmget').callsArgWith 2, null, [json]
        Document.get documents[0]._id, (error, result) ->
          err = error
          instance = result
          done()

      after ->
        rclient.hmget.restore()

      it 'should provide null error', ->
        expect(err).to.be.null

      it 'should provide an instance', ->
        expect(instance).to.be.instanceof Document

      it 'should not initialize private properties', ->
        expect(instance.secret).to.be.undefined


    describe 'by string not found', ->

      before (done) ->
        Document.get 'unknown', (error, result) ->
          err = error
          instance = result
          done()

      it 'should provide null error', ->
        expect(err).to.be.null

      it 'should provide a null result', ->
        expect(instance).to.be.null


    describe 'by array', ->

      before (done) ->
        sinon.stub(rclient, 'hmget').callsArgWith 2, null, jsonDocuments
        Document.get ids, (error, results) ->
          err = error
          instances = results
          done()

      after ->
        rclient.hmget.restore()

      it 'should provide null error', ->
        expect(err).to.be.null

      it 'should provide a list of instances', ->
        instances.length.should.equal 10
        instances.forEach (instance) ->
          expect(instance).to.be.instanceof Document

      it 'should not initialize private properties', ->
        instances.forEach (instance) ->
          expect(instance.secret).to.be.undefined


    describe 'by array not found', ->

      it 'should provide a null error'
      it 'should provide a list of instances'
      it 'should not provide null values in the list'


    describe 'with empty array', ->

      before (done) ->
        Document.get [], (error, results) ->
          err = error
          instances = results
          done()

      it 'should provide a null error', ->
        expect(err).to.be.null

      it 'should provide an empty array', ->
        Array.isArray(instances).should.be.true
        instances.length.should.equal 0


    describe 'with selection', ->

      before (done) ->
        sinon.spy rclient, 'zrevrange'
        sinon.stub(rclient, 'hmget').callsArgWith 2, null, jsonDocuments
        Document.get ids, { select: [ 'description', 'secret' ] }, (error, results) ->
          err = error
          instances = results
          done()

      after ->
        rclient.hmget.restore()
        rclient.zrevrange.restore()

      it 'should provide null error', ->
        expect(err).to.be.null

      it 'should provide a list of instances', ->
        instances.length.should.equal 10
        instances.forEach (instance) ->
          expect(instance).to.be.instanceof Document

      it 'should only initialize selected properties', ->
        instances.forEach (instance) ->
          expect(instance._id).to.be.undefined
          instance.description.should.be.a.string

      it 'should initialize private properties if selected', ->
        instances.forEach (instance) ->
          instance.secret.should.be.a.string


    describe 'with private option', ->

      before (done) ->
        document = documents[0]
        json = jsonDocuments[0]
        sinon.stub(rclient, 'hmget').callsArgWith 2, null, [json]
        Document.get documents[0]._id, { private: true }, (error, result) ->
          err = error
          instance = result
          done()

      after ->
        rclient.hmget.restore()

      it 'should provide null error', ->
        expect(err).to.be.null

      it 'should provide an instance', ->
        expect(instance).to.be.instanceof Document

      it 'should initialize private properties', ->
        expect(instance.secret).to.equal 'nobody knows'





  describe 'insert', ->

    describe 'with valid data', ->

      beforeEach (done) ->
        sinon.spy multi, 'hset'
        sinon.spy multi, 'zadd'
        sinon.spy Document, 'index'
        sinon.stub(Document, 'enforceUnique').callsArgWith(1, null)

        Document.insert data[0], (error, result) ->
          err = error
          instance = result
          done()

      afterEach ->
        multi.hset.restore()
        multi.zadd.restore()
        Document.index.restore()
        Document.enforceUnique.restore()

      it 'should provide a null error', ->
        expect(err).to.be.null

      it 'should provide the inserted instance', ->
        expect(instance).to.be.instanceof Document

      it 'should not provide private properties', ->
        expect(instance.secret).to.be.undefined

      it 'should store the serialized instance by unique id', ->
        multi.hset.should.have.been.calledWith 'documents', instance._id, sinon.match('"secret":"nobody knows"')

      it 'should index the instance', ->
        Document.index.should.have.been.calledWith sinon.match.object, sinon.match(instance)


    describe 'with invalid data', ->

      before (done) ->
        sinon.spy multi, 'hset'
        sinon.spy multi, 'zadd'
        sinon.spy Document, 'index'

        Document.insert {}, (error, result) ->
          err = error
          instance = result
          done()

      after ->
        multi.hset.restore()
        multi.zadd.restore()
        Document.index.restore()

      it 'should provide a validation error', ->
        err.should.be.instanceof Modinha.ValidationError

      it 'should not provide an instance', ->
        expect(instance).to.be.undefined

      it 'should not store the data', ->
        multi.hset.should.not.have.been.called

      it 'should not index the data', ->
        Document.index.should.not.have.been.called


    describe 'with private values option', ->

      beforeEach (done) ->
        sinon.spy multi, 'hset'
        sinon.spy multi, 'zadd'
        sinon.spy Document, 'index'
        sinon.stub(Document, 'enforceUnique').callsArgWith(1, null)

        Document.insert data[0], { private: true }, (error, result) ->
          err = error
          instance = result
          done()

      afterEach ->
        multi.hset.restore()
        multi.zadd.restore()
        Document.index.restore()
        Document.enforceUnique.restore()

      it 'should provide a null error', ->
        expect(err).to.be.null

      it 'should provide the inserted instance', ->
        expect(instance).to.be.instanceof Document

      it 'should provide private properties', ->
        expect(instance.secret).to.equal 'nobody knows'


    describe 'with duplicate unique values', ->

      beforeEach (done) ->
        sinon.spy multi, 'hset'
        sinon.spy multi, 'zadd'
        sinon.spy Document, 'index'
        sinon.stub(Document, 'getByUnique')
          .callsArgWith 1, null, documents[0]

        Document.insert data[0], (error, result) ->
          err = error
          instance = result
          done()

      afterEach ->
        multi.hset.restore()
        multi.zadd.restore()
        Document.index.restore()
        Document.getByUnique.restore()

      it 'should provide a unique value error', ->
        expect(err).to.be.instanceof Document.UniqueValueError

      it 'should not provide an instance', ->
        expect(instance).to.be.undefined


    describe 'with empty data', ->
    describe 'with mapping', ->
    describe 'with selection', ->
    describe 'with projection', ->




  describe 'replace', ->

    describe 'with valid data', ->

      before (done) ->
        doc = documents[0]
        update =
          _id: doc._id
          description: 'updated'

        sinon.stub(Document, 'get').callsArgWith(2, null, doc)
        sinon.spy Document, 'reindex'
        sinon.spy multi, 'hset'
        sinon.spy multi, 'zadd'

        Document.replace doc._id, update, (error, result) ->
          err = error
          instance = result
          done()

      after ->
        Document.get.restore()
        Document.reindex.restore()
        multi.hset.restore()
        multi.zadd.restore()

      it 'should provide a null error', ->
        expect(err).to.be.null

      it 'should provide the replaced instance', ->
        expect(instance).to.be.instanceof Document

      it 'should not provide private properties', ->
        expect(instance.secret).to.be.undefined

      it 'should replace the existing instance', ->
        expect(instance.description).to.equal 'updated'
        expect(instance.secret).to.be.undefined
        expect(instance.secondary).to.be.undefined

      it 'should reindex the instance', ->
        Document.reindex.should.have.been.calledWith sinon.match.object, sinon.match(update), documents[0]


    describe 'with unknown document', ->

      before (done) ->
        sinon.stub(Document, 'get').callsArgWith(2, null, null)
        Document.replace 'unknown', {}, (error, result) ->
          err = error
          instance = result
          done()

      after ->
        Document.get.restore()

      it 'should provide an null error', ->
        expect(err).to.be.null

      it 'should not provide an instance', ->
        expect(instance).to.be.null


    describe 'with invalid data', ->

      before (done) ->
        doc = documents[0]

        Document.replace doc._id, { description: -1 }, (error, result) ->
          err = error
          instance = result
          done()

      it 'should provide a validation error', ->
        expect(err).to.be.instanceof Modinha.ValidationError

      it 'should not provide an instance', ->
        expect(instance).to.be.undefined


    describe 'with private values option', ->

      before (done) ->
        doc = documents[0]
        json = jsonDocuments[0]

        sinon.stub(rclient, 'hmget').callsArgWith(2, null, [json])
        sinon.spy Document, 'reindex'
        sinon.spy multi, 'hset'
        sinon.spy multi, 'zadd'

        update =
          _id: doc._id
          description: 'updated'
          secret: 'still a secret'

        Document.replace doc._id, update, { private: true }, (error, result) ->
          err = error
          instance = result
          done()

      after ->
        rclient.hmget.restore()
        Document.reindex.restore()
        multi.hset.restore()
        multi.zadd.restore()

      it 'should provide a null error', ->
        expect(err).to.be.null

      it 'should provide the replaced instance', ->
        expect(instance).to.be.instanceof Document

      it 'should provide private properties', ->
        expect(instance.secret).to.equal 'still a secret'


    describe 'with duplicate unique values', ->

      beforeEach (done) ->
        doc1 = documents[0]
        doc2 = Document.initialize(documents[1]) # copy this doc
        doc2.unique = doc1.unique
        sinon.spy Document, 'index'
        sinon.stub(Document, 'get').callsArgWith(2, null, doc2)
        sinon.stub(Document, 'getByUnique')
          .callsArgWith 1, null, doc1

        Document.replace doc2._id, doc2, (error, result) ->
          err = error
          instance = result
          done()

      afterEach ->
        Document.get.restore()
        Document.index.restore()
        Document.getByUnique.restore()

      it 'should provide a unique value error', ->
        expect(err).to.be.instanceof Document.UniqueValueError

      it 'should not provide an instance', ->
        expect(instance).to.be.undefined



    describe 'with empty data', ->
    describe 'with mapping', ->
    describe 'with selection', ->
    describe 'with projection', ->




  describe 'patch', ->

    describe 'with valid data', ->

      before (done) ->
        doc = documents[0]
        json = jsonDocuments[0]

        sinon.stub(rclient, 'hmget').callsArgWith(2, null, [json])
        sinon.spy Document, 'reindex'
        sinon.spy multi, 'hset'
        sinon.spy multi, 'zadd'

        update =
          _id: doc._id
          description: 'updated'


        Document.patch doc._id, update, (error, result) ->
          err = error
          instance = result
          done()

      after ->
        rclient.hmget.restore()
        Document.reindex.restore()
        multi.hset.restore()
        multi.zadd.restore()

      it 'should provide a null error', ->
        expect(err).to.be.null

      it 'should provide the patched instance', ->
        expect(instance).to.be.instanceof Document

      it 'should not provide private properties', ->
        expect(instance.secret).to.be.undefined

      it 'should not generate default values', ->
        instance._id.should.equal documents[0]._id
        instance.created.should.equal documents[0].created

      it 'should update the "modified" timestamp', ->
        instance.modified.should.not.equal documents[0].created

      it 'should overwrite the stored data', ->
        multi.hset.should.have.been.calledWith 'documents', instance._id, sinon.match('"description":"updated"')

      it 'should reindex the instance', ->
        Document.reindex.should.have.been.calledWith sinon.match.object, sinon.match(update), sinon.match(documents[0])


    describe 'with unknown document', ->

      before (done) ->
        sinon.stub(Document, 'get').callsArgWith(2, null, null)
        Document.patch 'unknown', {}, (error, result) ->
          err = error
          instance = result
          done()

      after ->
        Document.get.restore()

      it 'should provide an null error', ->
        expect(err).to.be.null

      it 'should not provide an instance', ->
        expect(instance).to.be.null


    describe 'with invalid data', ->

      before (done) ->
        doc = documents[0]
        json = jsonDocuments[0]

        sinon.stub(rclient, 'hmget').callsArgWith(2, null, [json])
        sinon.spy multi, 'hset'
        sinon.spy multi, 'zadd'

        Document.patch doc._id, { description: -1 }, (error, result) ->
          err = error
          instance = result
          done()

      after ->
        rclient.hmget.restore()
        multi.hset.restore()
        multi.zadd.restore()

      it 'should provide a validation error', ->
        expect(err).to.be.instanceof Modinha.ValidationError

      it 'should not provide an instance', ->
        expect(instance).to.be.undefined


    describe 'with private values option', ->

      before (done) ->
        doc = documents[0]
        json = jsonDocuments[0]

        sinon.stub(rclient, 'hmget').callsArgWith(2, null, [json])
        sinon.spy Document, 'reindex'
        sinon.spy multi, 'hset'
        sinon.spy multi, 'zadd'

        update =
          _id: doc._id
          description: 'updated'


        Document.patch doc._id, update, { private:true }, (error, result) ->
          err = error
          instance = result
          done()

      after ->
        rclient.hmget.restore()
        Document.reindex.restore()
        multi.hset.restore()
        multi.zadd.restore()

      it 'should provide a null error', ->
        expect(err).to.be.null

      it 'should provide the replaced instance', ->
        expect(instance).to.be.instanceof Document

      it 'should provide private properties', ->
        expect(instance.secret).to.be.a.string


    describe 'with duplicate unique values', ->

      beforeEach (done) ->
        doc1 = documents[0]
        doc2 = documents[1]
        update = Document.initialize(documents[1]) # copy this doc
        update.unique = doc1.unique

        sinon.spy multi, 'hset'
        sinon.spy multi, 'zadd'
        sinon.spy Document, 'index'
        sinon.stub(Document, 'get')
          .callsArgWith 2, null, doc2
        sinon.stub(Document, 'getByUnique')
          .callsArgWith 1, null, doc1

        Document.patch doc2._id, update, (error, result) ->
          err = error
          instance = result
          done()

      afterEach ->
        multi.hset.restore()
        multi.zadd.restore()
        Document.index.restore()
        Document.get.restore()
        Document.getByUnique.restore()

      it 'should provide a unique value error', ->
        expect(err).to.be.instanceof Document.UniqueValueError

      it 'should not provide an instance', ->
        expect(instance).to.be.undefined


    describe 'with empty data', ->
    describe 'with mapping', ->
    describe 'with selection', ->
    describe 'with projection', ->




  describe 'delete', ->

    describe 'by string', ->

      before (done) ->
        instance = documents[0]
        sinon.spy Document, 'deindex'
        sinon.spy multi, 'hdel'
        sinon.stub(Document, 'get').callsArgWith(2, null, instance)
        Document.delete instance._id, (error, result) ->
          err = error
          deleted = result
          done()

      after ->
        Document.deindex.restore()
        Document.get.restore()
        multi.hdel.restore()

      it 'should provide a null error', ->
        expect(err).to.be.null

      it 'should provide confirmation', ->
        deleted.should.be.true

      it 'should remove the stored instance', ->
        multi.hdel.should.have.been.calledWith 'documents', instance._id

      it 'should deindex the instance', ->
        Document.deindex.should.have.been.calledWith sinon.match.object, sinon.match(instance)


    describe 'with unknown document', ->

      before (done) ->
        sinon.stub(Document, 'get').callsArgWith(2, null, null)
        Document.delete 'unknown', (error, result) ->
          err = error
          instance = result
          done()

      after ->
        Document.get.restore()

      it 'should provide an null error', ->
        expect(err).to.be.null

      it 'should not provide an instance', ->
        expect(instance).to.be.null


    describe 'by array', ->

      beforeEach (done) ->
        sinon.spy Document, 'deindex'
        sinon.spy multi, 'hdel'
        sinon.stub(Document, 'get').callsArgWith(2, null, documents)
        Document.delete ids, (error, result) ->
          err = error
          deleted = result
          done()

      afterEach ->
        Document.deindex.restore()
        Document.get.restore()
        multi.hdel.restore()

      it 'should provide a null error', ->
        expect(err).to.be.null

      it 'should provide confirmation', ->
        deleted.should.be.true

      it 'should remove each stored instance', ->
        multi.hdel.should.have.been.calledWith 'documents', ids

      it 'should deindex each instance', ->
        documents.forEach (doc) ->
          Document.deindex.should.have.been.calledWith sinon.match.object, doc



  describe 'index definitions', ->

    {indices} = {}

    before ->
      indices = Document.__indices

    it 'should include the unique id by timestamps', ->
      indices[3].type.should.equal 'sorted'
      indices[3].key.should.contain 'documents:created'
      indices[3].score.should.equal 'created'
      indices[3].member.should.equal Document.uniqueId
      indices[4].type.should.equal 'sorted'
      indices[4].key.should.contain 'documents:modified'
      indices[4].score.should.equal 'modified'
      indices[4].member.should.equal Document.uniqueId

    it 'should include "unique" schema properties', ->
      indices[0].type.should.equal 'hash'
      indices[0].key.should.equal 'documents:unique'
      indices[0].field.should.equal 'unique'
      indices[0].value.should.equal Document.uniqueId

    it 'should include "secondary" schema properties', ->
      indices[1].type.should.equal 'sorted'
      indices[1].key[0].should.equal 'documents:#:$'
      indices[1].key[1].should.equal 'secondary'
      indices[1].key[2].should.equal 'secondary'
      indices[1].score.should.equal 'modified'
      indices[1].member.should.equal Document.uniqueId

    it 'should include "reference" schema properties', ->
      indices[2].type.should.equal 'sorted'
      indices[2].key[0].should.equal 'references:$:documents'
      indices[2].key[1].should.equal 'reference'
      indices[2].score.should.equal 'created'
      indices[2].member.should.equal Document.uniqueId

    it 'should include "order" schema properties'



  describe 'index', ->

    before ->
      m = client.multi()
      instance = documents[0]
      sinon.spy multi, 'hset'
      sinon.spy multi, 'zadd'
      Document.index m, instance

    after ->
      multi.hset.restore()
      multi.zadd.restore()

    it 'should index an object by unique values', ->
      multi.hset.should.have.been.calledWith 'documents:unique', instance.unique, instance._id

    it 'should index an object by descriptive values', ->
      multi.zadd.should.have.been.calledWith "documents:secondary:#{instance.secondary}", instance.created, instance._id

    it 'should index an object by multiple values'

    it 'should index an object by creation time', ->
      multi.zadd.should.have.been.calledWith 'documents:created', instance.created, instance._id

    it 'should index an object by modification time', ->
      multi.zadd.should.have.been.calledWith 'documents:modified', instance.modified, instance._id

    it 'should index an object by reference', ->
      multi.zadd.should.have.been.calledWith "references:#{instance.reference}:documents", instance.created, instance._id




  describe 'deindex', ->

    before ->
      m = client.multi()
      instance = documents[0]
      sinon.spy multi, 'hdel'
      sinon.spy multi, 'zrem'
      Document.deindex m, instance

    after ->
      multi.hdel.restore()
      multi.zrem.restore()

    it 'should remove an object from unique index', ->
      multi.hdel.should.have.been.calledWith 'documents:unique', instance.unique

    it 'should remove an object from secondary index', ->
      multi.zrem.should.have.been.calledWith "documents:secondary:#{instance.secondary}", instance._id

    it 'should remove an object from created index', ->
      multi.zrem.should.have.been.calledWith 'documents:created', instance._id

    it 'should remove an object from modified index', ->
      multi.zrem.should.have.been.calledWith 'documents:modified', instance._id

    it 'should remove an object from a referenced object index', ->
      multi.zrem.should.have.been.calledWith "references:#{instance.reference}:documents", instance._id



  describe 'reindex', ->

    beforeEach ->
      sinon.spy multi, 'hset'
      sinon.spy multi, 'zadd'
      sinon.spy multi, 'hdel'
      sinon.spy multi, 'zrem'

    afterEach ->
      multi.hset.restore()
      multi.zadd.restore()
      multi.hdel.restore()
      multi.zrem.restore()


    describe 'with changed unique value', ->

      beforeEach ->
        m = client.multi()
        Document.reindex m, { _id: 'id', unique: 'updated' }, { _id: 'id', unique: 'original' }

      it 'should index the object id by new value', ->
        multi.hset.should.have.been.calledWith 'documents:unique', 'updated', 'id'

      it 'should deindex the object id by old value', ->
        multi.hdel.should.have.been.calledWith 'documents:unique', 'original'


    describe 'with unchanged unique value', ->

      beforeEach ->
        m = client.multi()
        Document.reindex m, { _id: 'id', unique: 'original' }, { _id: 'id', unique: 'original' }

      it 'should not reindex the value', ->
        multi.hset.should.not.have.been.called
        multi.hdel.should.not.have.been.called


    describe 'with changed secondary value', ->

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

      it 'should index the object id by new value', ->
        multi.zadd.should.have.been
          .calledWith 'documents:secondary:updated', instance.modified, instance._id

      it 'should deindex the object id by old value', ->
        multi.zrem.should.have.been
          .calledWith 'documents:secondary:original', instance._id


    describe 'with unchanged secondary value', ->

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


    describe 'with changed ordered value', ->

      beforeEach ->
        m = client.multi()

        instance =
          _id: 'id'
          modified: '1235'
        original =
          _id: 'id'
          modified: '1234'

        Document.reindex m, instance, original

      it 'should reindex the object id with a new score', ->
        multi.zadd.should.have.been.calledWith 'documents:modified', instance.modified, instance._id


    describe 'with unchanged ordered value', ->

      beforeEach ->
        m = client.multi()

        instance =
          _id: 'id'
          modified: '1234'

        Document.reindex m, instance, instance

      it 'should not reindex the object id with a new score', ->
        multi.zadd.should.not.have.been.called


    describe 'with changed reference value', ->

      beforeEach ->
        m = client.multi()

        instance =
          _id: 'id'
          reference: '1235'
          created: '3456'
        original =
          _id: 'id'
          reference: '1234'

        Document.reindex m, instance, original

      it 'should index the object id by new reference', ->
        multi.zadd.should.have.been.calledWith "references:#{instance.reference}:documents", instance.created, instance._id

      it 'should deindex the object id by old reference', ->
        multi.zrem.should.have.been.calledWith "references:#{original.reference}:documents", instance._id


    describe 'with unchanged reference value', ->

      beforeEach ->
        m = client.multi()

        instance =
          _id: 'id'
          reference: '1235'

        Document.reindex m, instance, instance

      it 'should not reindex the object id by reference', ->
        multi.zadd.should.not.have.been.called
        multi.zrem.should.not.have.been.called




  describe 'get by unique index', ->

    describe 'with known value', ->

      before (done) ->
        doc  = documents[0]
        json = jsonDocuments[0]

        sinon.stub(rclient, 'hget')
          .callsArgWith 2, null, doc._id
        sinon.stub(rclient, 'hmget')
          .callsArgWith 2, null, json

        Document.getByUnique doc._id, (error, result) ->
          err = error
          instance = result
          done()

      after ->
        rclient.hmget.restore()
        rclient.hget.restore()

      it 'should provide a null error', ->
        expect(err).to.be.null

      it 'should provide an instance', ->
        expect(instance).to.be.instanceof Document




  describe 'enforce unique', ->

    describe 'with unique values', ->

      before (done) ->
        sinon.stub(Document, 'getByUnique').callsArgWith 1, null, null
        Document.enforceUnique documents[0], (error) ->
          err = error
          done()

      after ->
        Document.getByUnique.restore()

      it 'should provide a null error', ->
        expect(err).to.be.null


    describe 'with duplicated values', ->

      before (done) ->
        doc1 = documents[0]
        doc2 = Document.initialize(documents[1]) # copy this doc
        doc2.unique = doc1.unique
        sinon.stub(Document, 'getByUnique').callsArgWith 1, null, doc1
        Document.enforceUnique doc2, (error) ->
          err = error
          done()

      after ->
        Document.getByUnique.restore()

      it 'should provide a UniqueValueError', ->
        err.message.should.equal 'unique must be unique'




  describe 'list by secondary index', ->

      before (done) ->
        sinon.stub(rclient, 'zrevrange').callsArgWith(3, null, ids)
        sinon.stub(rclient, 'hmget').callsArgWith(2, null, documents)
        Document.listBySecondary 'value', (error, results) ->
          err = error
          instances = results
          done()

      after ->
        rclient.zrevrange.restore()
        rclient.hmget.restore()

      it 'should provide a null error', ->
        expect(err).to.be.null

      it 'should provide instances', ->
        instances.forEach (instance) ->
          expect(instance).to.be.instanceof Document


  describe 'list by reference', ->

      before (done) ->
        sinon.stub(rclient, 'zrevrange').callsArgWith(3, null, ids)
        sinon.stub(rclient, 'hmget').callsArgWith(2, null, documents)
        Document.listByReference 'id', (error, results) ->
          err = error
          instances = results
          done()

      after ->
        rclient.zrevrange.restore()
        rclient.hmget.restore()

      it 'should provide a null error', ->
        expect(err).to.be.null

      it 'should provide instances', ->
        instances.forEach (instance) ->
          expect(instance).to.be.instanceof Document


  describe 'list newest', ->

    before (done) ->
      sinon.stub(rclient, 'zrevrange').callsArgWith(3, null, ids)
      sinon.stub(rclient, 'hmget').callsArgWith(2, null, documents)
      Document.listNewest (error, result) ->
       err = error
       instances = result
       done()

    after ->
      rclient.zrevrange.restore()
      rclient.hmget.restore()

    it 'should provide a null error', ->
      expect(err).to.be.null

    it 'should provide a list of instances', ->
      instances.forEach (instance) ->
        expect(instance).to.be.instanceof Document

    it 'should provide results in reverse chronological order', ->
      rclient.zrevrange.should.have.been.called

    it 'should look in the correct index', ->
      rclient.zrevrange.should.have.been.calledWith 'documents:created'




  describe 'list earliest', ->

    before (done) ->
      sinon.stub(rclient, 'zrange').callsArgWith(3, null, ids)
      sinon.stub(rclient, 'hmget').callsArgWith(2, null, documents)
      Document.listEarliest (error, result) ->
       err = error
       instances = result
       done()

    after ->
      rclient.zrange.restore()
      rclient.hmget.restore()

    it 'should provide a null error', ->
      expect(err).to.be.null

    it 'should provide a list of instances', ->
      instances.forEach (instance) ->
        expect(instance).to.be.instanceof Document

    it 'should provide results in chronological order', ->
      rclient.zrange.should.have.been.called

    it 'should look in the correct index', ->
      rclient.zrange.should.have.been.calledWith 'documents:created'




  describe 'list in chronological order by modification time', ->
  describe 'list in reverse chronological order by modification time', ->



