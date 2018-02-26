import UIKit
import CoreMotion
import CoreLocation
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
var manager = CLLocationManager()

@objc(CordovaStepCounter) class CordovaStepCounter : CDVPlugin, CLLocationManagerDelegate {
    let activityManager = CMMotionActivityManager()
    var db: SQLInterface?
    var latitude: Double = 0.0
    var longitude: Double = 0.0
    var speed: Double = 0.0
    
    override func pluginInitialize() {
        pedometer = CMPedometer()
        self.initDb()
        self.initLocationManager()
    }
    
    func initLocationManager() {
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        
//        if use location indicavtor, comment out
//        if #available(iOS 11.0, *) {
//            manager.showsBackgroundLocationIndicator = true
//        }
        
        manager.activityType = CLActivityType.fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.latitude = locations[0].coordinate.latitude
        self.longitude = locations[0].coordinate.longitude
        self.speed = locations[0].speed
    }
    
    @objc(start:) func start(command: CDVInvokedUrlCommand) {
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
        }
        
        self.commandDelegate!.send(
            pluginResult,
            callbackId: command.callbackId
        )
    }
    
    @objc(stop:) func stop(command: CDVInvokedUrlCommand) {
        if let pedo = pedometer {
            pedo.stopUpdates()
        }
    }
    
    @objc(can_count_steps:) func can_count_steps(command: CDVInvokedUrlCommand) {
        
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
        
        let latestStepsId = command.arguments[0] as! NSNumber
        
        if let dbExist = self.db {
            do {
                try dbExist.reset_step_count(latestStepsId: latestStepsId)
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
        self.db = SQLInterface()
    }
    
    func onWalk(data: CMPedometerData?, err: Error?) -> Void {
        if err != nil {

            return
        }
        
        if let dataExist = data {
            if let dbExist = self.db {
                do {
                    try dbExist.insert_value(startDate: dataExist.startDate, endDate: dataExist.endDate, stepCount: dataExist.numberOfSteps, latitude: self.latitude, longitude: self.longitude, speed: self.speed)
                } catch {
                    
                }
            }
        }
        
        if let errExist = err {
        }
    }
}



func checkCountingAvailable() -> Bool {
    if !CMPedometer.isStepCountingAvailable() {

        return false;
    }
    
    if !CMPedometer.isDistanceAvailable() {

    }
    
    if !CMPedometer.isFloorCountingAvailable() {

    }
    
    if !CMPedometer.isCadenceAvailable() {

    }
    
    if #available(iOS 10.0, *) {
        if !CMPedometer.isPedometerEventTrackingAvailable() {
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
        abort()
    }()
    
    override init() {
        super.init()
        do {
            try self.prepare_database()
        } catch {

            abort()
        }
    }
    
    func prepare_database() throws {
        defer { sqlite3_finalize(stmt) }
        
        let query = "CREATE TABLE IF NOT EXISTS steps (_id integer PRIMARY KEY autoincrement, startDate integer, endDate integer, stepCount integer, latitude real, longitude real, speed real, synced integer)"
        
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
    
    func insert_value(startDate: Date, endDate: Date, stepCount: NSNumber, latitude: Double, longitude: Double, speed: Double) throws {
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
        
        let query = "INSERT INTO steps (startDate, endDate, stepCount, latitude, longitude, speed, synced) VALUES (?, ?, ?, ?, ?, ?, ?)"
        
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(startDate.timeIntervalSince1970 * 1000))
            sqlite3_bind_int64(stmt, 2, Int64(endDate.timeIntervalSince1970 * 1000))
            sqlite3_bind_int(stmt, 3, Int32(latestValue))
            sqlite3_bind_double(stmt, 4, latitude)
            sqlite3_bind_double(stmt, 5, longitude)
            sqlite3_bind_double(stmt, 6, speed)
            sqlite3_bind_int(stmt, 7, 0)
            if sqlite3_step(stmt) == SQLITE_DONE { return }
        }
        throw SQLError.QueryError
    }
    
    func reset_step_count(latestStepsId: NSNumber) throws {
        defer { sqlite3_finalize(stmt) }
        let resetQury = "UPDATE steps SET synced = 1 WHERE _id <= \(latestStepsId)"
        
        if sqlite3_prepare_v2(db, resetQury, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_DONE {return}
        }
        throw SQLError.QueryError
    }
}
