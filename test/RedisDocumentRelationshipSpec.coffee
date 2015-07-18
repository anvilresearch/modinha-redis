## Test dependencies
cwd       = process.cwd()
path      = require 'path'
#Faker     = require 'Faker'
chai      = require 'chai'
sinon     = require 'sinon'
sinonChai = require 'sinon-chai'
expect    = chai.expect




## Configure Chai and Sinon
chai.use sinonChai
chai.should()




## Code under test
Modinha       = require 'modinha'
RedisDocument = require path.join(cwd, 'lib/RedisDocument')




## Redis lib for spying and stubbing
redis   = require 'redis'
client  = redis.createClient()
multi   = redis.Multi.prototype
rclient = redis.RedisClient.prototype




describe 'Intersect', ->


  {LeftModel,RightModel,left,right} = {}


  before ->
    LeftModel = Modinha.define 'lefts', name: { type: 'string' }
    RightModel = Modinha.define 'rights', name: { type: 'string' }

    LeftModel.extend RedisDocument
    RightModel.extend RedisDocument

    LeftModel.intersects 'rights'
    RightModel.intersects 'lefts'

    LeftModel.__client = client
    RightModel.__client = client

  it 'should define an add method on the constructor', ->
    LeftModel.addRights.should.be.a.function

  it 'should define an add method on the prototype', ->
    LeftModel.prototype.addRights.should.be.a.function

  it 'should define a remove method on the constructor', ->
    LeftModel.removeRights.should.be.a.function

  it 'should define a remove method on the prototype', ->
    LeftModel.prototype.removeRights.should.be.a.function

  it 'should define a list method on the constructor', ->
    LeftModel.listByRights.should.be.a.function





  describe 'add', ->

    describe 'with object args', ->

      before (done) ->
        left = new LeftModel
        right = new RightModel

        sinon.stub multi, 'zadd'
        sinon.stub(multi, 'exec').callsArgWith 0, null, []

        #sinon.spy multi, 'zadd'
        LeftModel.addRights left, right, done

      after ->
        multi.zadd.restore()
        multi.exec.restore()

      it 'should index the left model by the right model', ->
        multi.zadd.should.have.been.calledWith "rights:#{right._id}:lefts", sinon.match.number, left._id

      it 'should index the right model by the left model', ->
        multi.zadd.should.have.been.calledWith "lefts:#{left._id}:rights", sinon.match.number, right._id


    describe 'with id args', ->

      before (done) ->
        left = new LeftModel
        right = new RightModel

        sinon.stub multi, 'zadd'
        sinon.stub(multi, 'exec').callsArgWith 0, null, []

        LeftModel.addRights left._id, right._id, done

      after ->
        multi.zadd.restore()
        multi.exec.restore()

      it 'should index the left model by the right model', ->
        multi.zadd.should.have.been.calledWith "rights:#{right._id}:lefts", sinon.match.number, left._id

      it 'should index the right model by the left model', ->
        multi.zadd.should.have.been.calledWith "lefts:#{left._id}:rights", sinon.match.number, right._id




  describe 'remove', ->

    describe 'with object args', ->

      before (done) ->
        left = new LeftModel
        right = new RightModel

        sinon.stub multi, 'zrem'
        sinon.stub(multi, 'exec').callsArgWith 0, null, []
        LeftModel.removeRights left, right, done

      after ->
        multi.zrem.restore()
        multi.exec.restore()

      it 'should index the left model by the right model', ->
        multi.zrem.should.have.been.calledWith "rights:#{right._id}:lefts", left._id

      it 'should index the right model by the left model', ->
        multi.zrem.should.have.been.calledWith "lefts:#{left._id}:rights", right._id



    describe 'with id args', ->

      before (done) ->
        left = new LeftModel
        right = new RightModel

        sinon.stub multi, 'zrem'
        sinon.stub(multi, 'exec').callsArgWith 0, null, []
        LeftModel.removeRights left, right, done

      after ->
        multi.zrem.restore()
        multi.exec.restore()

      it 'should index the left model by the right model', ->
        multi.zrem.should.have.been.calledWith "rights:#{right._id}:lefts", left._id

      it 'should index the right model by the left model', ->
        multi.zrem.should.have.been.calledWith "lefts:#{left._id}:rights", right._id




  describe 'list', ->

    describe 'with object arg', ->

      before (done) ->
        right = new RightModel
        sinon.spy LeftModel, 'list'
        sinon.stub(rclient, 'zrange').callsArgWith 3, null, []
        sinon.stub(rclient, 'zrevrange').callsArgWith 3, null, []
        LeftModel.listByRights right, done

      after ->
        rclient.zrange.restore()
        rclient.zrevrange.restore()
        LeftModel.list.restore()

      it 'should look in the right index', ->
        LeftModel.list.should.have.been.calledWith { index: "rights:#{right._id}:lefts" }


    describe 'with id arg', ->

      before (done) ->
        right = new RightModel
        sinon.stub(rclient, 'zrange').callsArgWith 3, null, []
        sinon.stub(rclient, 'zrevrange').callsArgWith 3, null, []
        sinon.spy LeftModel, 'list'
        LeftModel.listByRights right._id, done

      after ->
        rclient.zrange.restore()
        rclient.zrevrange.restore()
        LeftModel.list.restore()

      it 'should look in the right index', ->
        LeftModel.list.should.have.been.calledWith { index: "rights:#{right._id}:lefts" }





