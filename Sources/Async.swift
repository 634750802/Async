import class Dispatch.DispatchQueue

///  Every task add to AsyncTask will be add to its
/// DispatchQueue, which is blocking at first. When
/// the task is done, call the unLock() method and
/// run next tasks.
///
///  The queue is a serail queue, so when the queue
/// resumes, the state must be done. Thus, every
/// successor tasks has the result value or error.
public struct AsyncTask<T> {
    private let _queue: _AsyncQueue<T>
    
    ///  Crate a new task without procedure. You must
    /// call `done` or `terminate` manually.
    public init() {
        self._queue = _AsyncQueue()
    }
    
    ///  Create a new task with procedure. You should
    /// resolve the task within the procedure.
    /// 
    ///  You can just throw an error to ternimate.
    ///
    /// - Parameter procedure: a sync procedure with
    ///  done and terminate closure.
    public init(_ procedure: (@escaping (T)->Void, @escaping (Error)->Void) throws -> Void) {
        self.init()
        do {
            try procedure(done, terminate)
        } catch let error {
            terminate(for: error)
        }
    }
    
    /// ** Do not call it more than once **,
    /// which will draw a fatal error.
    /// 
    /// - Parameter value: The result value
    public func done(_ value: T) {
        _queue.state = .done(.value(value))
    }
    
    /// ** Do not call it more than once **,
    /// which will draw a fatal error.
    ///
    /// - Parameter reason: The terminate reason
    public func terminate(for reason: Error ) {
        _queue.state = .done(.error(reason))
    }
    
    ///  Just like promise in JavaScript, when this task
    /// is done, do next.
    ///
    ///  When this task is terminated, next task will be
    /// terminated. Only when this task is done, next task
    /// will start to run.
    ///
    /// - Parameter procedure: Next task.
    /// - Returns: Next task object.
    @discardableResult
    public func next<S>(_ procedure: @escaping (T) throws -> S) -> AsyncTask<S> {
        let promise = AsyncTask<S>.init()
        _queue.async { ()->Void in
            do {
                let result = self._queue.state.assertResult
                
                switch result {
                case .value(let t):
                    promise.done(try procedure(t))
                case .error(let err):
                    throw err
                }
            }catch let error {
                promise.terminate(for: error)
            }
        }
        return promise
    }
    
    ///  Catch any terminate **uncatched** reason.
    /// Only terminated when Error type is not correct.
    ///
    /// - Parameter procedure: Error handle task.
    /// - Returns: task object
    @discardableResult
    public func `catch`<E>(_ procedure: @escaping (E) -> Void ) -> AsyncTask<Void> {
        let promise = AsyncTask<Void>.init()
        _queue.async { ()->Void in
            switch self._queue.state.assertResult {
            case .value(_):
                promise.done()
            case .error(let err):
                if let error = err as? E {
                    promise.done(procedure(error))
                } else {
                    promise.terminate(for: err)
                }
            }
        }
        return promise
    }
    
    ///  Synchorize task result.
    ///
    /// - Throws: if the task was terminated.
    /// - Returns: the task's result.
    public func sync() throws -> T {
        return try _queue.sync {
            switch _queue.state.assertResult {
            case .value(let t):
                return t
            case .error(let err):
                throw err
            }
        }
    }
}

private enum _AsyncTaskResult<T> {
    case value(T)
    case error(Error)
}

private enum _AsyncTaskState<T> {
    case pending
    case done(_AsyncTaskResult<T>)
    
    var assertResult: _AsyncTaskResult<T> {
        switch self {
        case .done(let result):
            return result
        default: fatalError()
        }
    }
    
}

private class _AsyncQueue<T> {
    
    private let queue = DispatchQueue(label: "async task queue")
    fileprivate var state: _AsyncTaskState<T> = .pending {
        didSet {
            switch (oldValue, state) {
            case (.pending, .done(_)):
                unLock()
            default: fatalError()
            }
        }
    }
    private var hold: _AsyncQueue<T>? = nil
    
    init() {
        hold = self
        queue.suspend()
    }
    
    func sync<T>(_ block: () throws -> T ) rethrows -> T {
        return try queue.sync(execute: block)
    }
    
    func async(_ block: @escaping () -> Void ) {
        queue.async(execute: block)
    }
    
    private func unLock() {
        queue.resume()
        hold = nil
    }
    
}
