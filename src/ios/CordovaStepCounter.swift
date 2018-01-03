import UIKit
import CoreMotion
import Foundation

struct StepStruct {
    var startDate: Int64
    var endDate: Int64
    var stepCount: Int
    
    init(startDate: Int64, endDate: Int64, stepCount: Int) {
        self.startDate = startDate
        self.endDate = endDate
        self.stepCount = stepCount
    }
}

enum SQLError : Error {
    case ConnectionError
    case QueryError
    case OtherError
}

var pedometer: CMPedometer?

@objc(CordovaStepCounter) class CordovaStepCounter : CDVPlugin {
    let activityManager = CMMotionActivityManager()
    var db: SQLInterface?
    
    override func pluginInitialize() {
        print("initialize is called");
        pedometer = CMPedometer()
        self.initDb()
    }
    
    @objc(start:) func start(command: CDVInvokedUrlCommand) {
        print("start is called!!!")
        var pluginResult = CDVPluginResult(
            status: CDVCommandStatus_OK,
            messageAs: 1
        )
        
        if let dbExist = self.db {
            dbExist.previous = 0
            if let pedo = pedometer {
                pedo.startUpdates(from: Date(), withHandler: onWalk)
            }
        } else {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR)
            print("db가 존재하지 않습니다.")
        }
        
        self.commandDelegate!.send(
            pluginResult,
            callbackId: command.callbackId
        )
    }
    
    @objc(stop:) func stop(command: CDVInvokedUrlCommand) {
        print("stop is called!!!")
        if let pedo = pedometer {
            pedo.stopUpdates()
        }
    }
    
    @objc(can_count_steps:) func can_count_steps(command: CDVInvokedUrlCommand) {
        print("can_count_steps is called!!!")
        
        let pluginResult = CDVPluginResult(
            status: CDVCommandStatus_OK,
            messageAs: checkCountingAvailable() ? 1 : 0
        )
        
        self.commandDelegate!.send(
            pluginResult,
            callbackId: command.callbackId
        )
    }
    
    @objc(reset_step_count:) func reset_step_count(command: CDVInvokedUrlCommand) {
        print("reset_step_count is called!!!")
        
        let latestStepCount = command.arguments[0] as! NSNumber
        
        if let dbExist = self.db {
            do {
                try dbExist.reset_step_count(stepCount: latestStepCount)
            } catch {
                
            }
        }
        
        let pluginResult = CDVPluginResult(
            status: CDVCommandStatus_OK,
            messageAs: 1
        )
        
        self.commandDelegate!.send(
            pluginResult,
            callbackId: command.callbackId
        )
    }
    
    func initDb() {
        print("initDb is called!!!")
        self.db = SQLInterface()
    }
    
    func onWalk(data: CMPedometerData?, err: Error?) -> Void {
        print("onWalk is called!!!")
        if err != nil {
            print(err!)
            return
        }
        
        if let dataExist = data {
            print("시작 날짜 :\(dataExist.startDate)")
            print("끝나는 날짜 :\(dataExist.endDate)")
            print("걸음수 :\(dataExist.numberOfSteps)")
            
            if let dbExist = self.db {
                do {
                    try dbExist.insert_value(startDate: dataExist.startDate, endDate: dataExist.endDate, stepCount: dataExist.numberOfSteps)
                } catch {
                    
                }
            }
        }
        
        if let errExist = err {
            print(errExist)
        }
    }
}



func checkCountingAvailable() -> Bool {
    if !CMPedometer.isStepCountingAvailable() {
        print("걸음수 측정이 불가능한 기기 입니다.")
        return false;
    }
    
    if !CMPedometer.isDistanceAvailable() {
        print("거리측정이 불가능한 기기 입니다.")
    }
    
    if !CMPedometer.isFloorCountingAvailable() {
        print("층측정이 불가능한 기기 입니다.")
    }
    
    if !CMPedometer.isCadenceAvailable() {
        print("속도 측정이 불가능한 기기 입니다.")
    }
    
    if #available(iOS 10.0, *) {
        if !CMPedometer.isPedometerEventTrackingAvailable() {
            print("걸음수 이벤트 트랙킹이 불가능한 기기 입니다.")
        }
    }
    
    return true
}

class SQLInterface: NSObject {
    var previous = 0;
    var stmt: OpaquePointer? = nil
    
    lazy var db:OpaquePointer = {
        var _db:OpaquePointer? = nil
        let path = FileManager.default.urls(for:.documentDirectory, in:.userDomainMask)
            .last!.appendingPathComponent("getwalk.db").path
        if sqlite3_open(path, &_db) == SQLITE_OK {
            return _db!
        }
        print("Fail to connect database")
        abort()
    }()
    
    override init() {
        super.init()
        do {
            try self.prepare_database()
        } catch {
            print("Fail to init database")
            abort()
        }
    }
    
    func prepare_database() throws {
        defer { sqlite3_finalize(stmt) }
        
        let query = "CREATE TABLE IF NOT EXISTS steps (_id integer PRIMARY KEY autoincrement, startDate integer, endDate integer, stepCount integer)"
        
        if sqlite3_prepare(db, query, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_DONE {
                return
            }
        }
        throw SQLError.ConnectionError
    }
    
    
    deinit {
        sqlite3_close(db)
    }
    
    func insert_value(startDate: Date, endDate: Date, stepCount: NSNumber) throws {
        
        defer { sqlite3_finalize(stmt) }
        var latestValue = 0;
        let lastSelectQuery = "SELECT * FROM steps ORDER BY _id DESC LIMIT 1"
        if sqlite3_prepare(db, lastSelectQuery, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                latestValue = Int(sqlite3_column_int(stmt, 3))
            }
        }
        
        latestValue = latestValue + Int(truncating: stepCount) - self.previous
        self.previous = Int(truncating: stepCount)
        
        let query = "INSERT INTO steps (startDate, endDate, stepCount) VALUES (?, ?, ?)"
        
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(startDate.timeIntervalSince1970 * 1000))
            sqlite3_bind_int64(stmt, 2, Int64(endDate.timeIntervalSince1970 * 1000))
            sqlite3_bind_int(stmt, 3, Int32(latestValue))
            if sqlite3_step(stmt) == SQLITE_DONE { return }
        }
        throw SQLError.QueryError
    }
    
    func reset_step_count(stepCount: NSNumber) throws {
        defer { sqlite3_finalize(stmt) }
        let resetQury = "INSERT INTO steps (startDate, endDate, stepCount) VALUES (?, ?," +
            "((SELECT stepCount FROM steps ORDER BY _id DESC LIMIT 1) - \(stepCount)))"
        
        let currentDateTime = Date()
        
        if sqlite3_prepare_v2(db, resetQury, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(currentDateTime.timeIntervalSince1970 * 1000))
            sqlite3_bind_int64(stmt, 2, Int64(currentDateTime.timeIntervalSince1970 * 1000))
            if sqlite3_step(stmt) == SQLITE_DONE {return}
        } 
        throw SQLError.QueryError
    }
    
    func get_values() throws -> [StepStruct] {
        guard db != nil else { throw SQLError.ConnectionError }
        defer { sqlite3_finalize(stmt) }
        var result = [StepStruct]()
        let query = "SELECT * FROM steps"
        if sqlite3_prepare(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let stepCount = StepStruct(startDate: Int64(sqlite3_column_int64(stmt, 1)), endDate: Int64(sqlite3_column_int64(stmt, 2)), stepCount: Int(sqlite3_column_int(stmt, 3)))
                result.append(stepCount)
            }
            return result
        }
        throw SQLError.QueryError
    }
}
