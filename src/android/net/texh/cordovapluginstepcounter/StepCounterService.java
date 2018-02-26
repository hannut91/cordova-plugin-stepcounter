package net.texh.cordovapluginstepcounter;

/*
    Copyright 2015 Jarrod Linahan <jarrod@texh.net>

    Permission is hereby granted, free of charge, to any person obtaining
    a copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be
    included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
    LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
    OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
    WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

 */

import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.location.Location;
import android.os.Binder;
import android.os.IBinder;
import android.util.Log;

import com.google.android.gms.location.FusedLocationProviderClient;
import com.google.android.gms.location.LocationCallback;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationResult;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.tasks.OnSuccessListener;

import java.util.Date;


public class StepCounterService extends Service implements SensorEventListener {

    private final String TAG = "StepCounterService";
    private IBinder mBinder = null;
    private SensorManager mSensorManager;
    private Sensor mStepSensor;
    private FusedLocationProviderClient mFusedLocationClient;
    SQLiteDatabase database;
    long startDate;
    double latitude = 0;
    double longitude = 0;
    float speed = 0;
    long locationTime;
    Location lastLocation;

    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(TAG, "StepCounterService onCreate is called!!");
        setLocation();
        openDatabase();
        createTable();
        startDate = new Date().getTime();
    }

    public void setLocation() {
        mFusedLocationClient = LocationServices.getFusedLocationProviderClient(this);
        LocationRequest mLocationRequest = new LocationRequest();
        mLocationRequest.setInterval(10000);
//        mLocationRequest.setFastestInterval(1000);
        mLocationRequest.setPriority(LocationRequest.PRIORITY_HIGH_ACCURACY);
        LocationCallback mLocationCallback = new LocationCallback() {
            @Override
            public void onLocationResult(LocationResult locationResult) {
                Location currentLocation = locationResult.getLastLocation();
                long currentTime = currentLocation.getTime();

                if(latitude == 0 || longitude == 0) {
                    latitude = currentLocation.getLatitude();
                    longitude = currentLocation.getLongitude();
                    speed = currentLocation.getSpeed();
                    locationTime = currentTime;
                    lastLocation = currentLocation;
                    return;
                }

                latitude = currentLocation.getLatitude();
                longitude = currentLocation.getLongitude();

                if(currentLocation.hasSpeed() && currentLocation.getSpeed() > 0) {
                    speed = currentLocation.getSpeed();
                } else {
                    speed = lastLocation.distanceTo(currentLocation) / ((currentTime - locationTime) / 1000);
                }

                locationTime = currentTime;
                lastLocation = locationResult.getLastLocation();

            }
        };

        try {
            mFusedLocationClient.requestLocationUpdates(mLocationRequest,
                    mLocationCallback,
                    null /* Looper */);
        } catch (SecurityException e) {

        }
    }

    public void openDatabase() {
        database = openOrCreateDatabase("getwalk.db", MODE_PRIVATE, null);
    }

    public void createTable() {
        if (database != null) {
            String sql = "CREATE TABLE IF NOT EXISTS steps (_id integer PRIMARY KEY autoincrement, startDate integer, endDate integer, stepCount integer, latitude real, longitude real, speed real, synced integer)";
            database.execSQL(sql);
        }
    }

    @Override
    public IBinder onBind(Intent intent) {
        mBinder = new StepCounterServiceBinder();
        Log.i(TAG, "onBind" + intent);
        return mBinder;
    }

    public class StepCounterServiceBinder extends Binder {
        StepCounterService getService() {
            return StepCounterService.this;
        }
    }


    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.i(TAG, "onStartCommand is called");
        mSensorManager = (SensorManager) getSystemService(SENSOR_SERVICE);
        mStepSensor = mSensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER);
        mSensorManager.registerListener(this, mStepSensor, SensorManager.SENSOR_DELAY_NORMAL);
        return Service.START_STICKY;
    }

    @Override
    public boolean stopService(Intent intent) {
        Log.i(TAG, "stopService is called" + intent);
        mSensorManager.unregisterListener(this);
        return super.stopService(intent);
    }

    @Override
    public void onSensorChanged(SensorEvent sensorEvent) {
        int stepCount = (int) sensorEvent.values[0];
        long endDate = new Date().getTime();
        insertData(stepCount, endDate);
    }

    public void insertData(int currentStepCount, long endDate) {
        if (database != null) {
            SharedPreferences sharedPref = getSharedPreferences("previousStepCount", Context.MODE_PRIVATE);
            int previous = sharedPref.getInt("previousStepCount", -1);
            Log.d(TAG, "currentStepCount" + currentStepCount);
            Log.d(TAG, "previous" + previous);

            if (previous < 0) {
                SharedPreferences.Editor editor = sharedPref.edit();
                editor.putInt("previousStepCount", currentStepCount);
                editor.commit();
                return;
            }


            String latestSelectQuery = "SELECT * FROM steps ORDER BY _id DESC LIMIT 1";
            Cursor cursor = database.rawQuery(latestSelectQuery, null);
            int latestStepCount = 0;

            if (cursor.getCount() > 0) {
                cursor.moveToNext();
                latestStepCount = cursor.getInt(3);
            }

            if(currentStepCount - previous < 0) {
                latestStepCount = previous + 1;
            } else {
                latestStepCount = latestStepCount + (currentStepCount - previous);
            }

            SharedPreferences.Editor editor = sharedPref.edit();
            editor.putInt("previousStepCount", currentStepCount);
            editor.commit();

            String sql = "INSERT INTO steps (startDate, endDate, stepCount, latitude, longitude, speed, synced) VALUES (?, ?, ?, ?, ?, ?, ?)";
            Object[] params = {startDate, endDate, latestStepCount, latitude, longitude, speed, 0};
            database.execSQL(sql, params);
        }
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int i) {
        Log.i(TAG, "onAccuracyChanged: " + sensor);
        Log.i(TAG, "  Accuracy: " + i);
    }

    @Override
    public boolean onUnbind(Intent intent) {
        Log.i(TAG, "onUnbind");
        return super.onUnbind(intent);
    }

    @Override
    public void onDestroy(){
        Log.i(TAG, "onDestroy");
        mSensorManager.unregisterListener(this);
    }
}
