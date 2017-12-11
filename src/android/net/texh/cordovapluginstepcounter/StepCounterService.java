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
import android.os.Binder;
import android.os.IBinder;
import android.util.Log;
import java.util.Date;


public class StepCounterService extends Service implements SensorEventListener {

    private final  String TAG = "StepCounterService";
    private IBinder mBinder = null;
    private SensorManager mSensorManager;
    private Sensor mStepSensor;
    SQLiteDatabase database;
    long startDate;

    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(TAG, "onCreate");
        openDatabase();
        createTable();
        startDate = new Date().getTime();
    }

    @Override
    public IBinder onBind(Intent intent) {
        mBinder   = new StepCounterServiceBinder();
        Log.i(TAG, "onBind" + intent);
        return mBinder;
    }

    public class StepCounterServiceBinder extends Binder {
        StepCounterService getService() {
            return StepCounterService.this;
        }
    }

    public void openDatabase() {
        database = openOrCreateDatabase("getwalk.db", MODE_PRIVATE, null);
    }

    public void createTable() {
        if(database  != null) {
            String sql = "CREATE TABLE IF NOT EXISTS steps (_id integer PRIMARY KEY autoincrement, startDate integer, endDate integer, stepCount integer)";
            database.execSQL(sql);
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.i(TAG, "onStartCommand is called");
        mSensorManager = (SensorManager) getSystemService(SENSOR_SERVICE);
        mStepSensor    = mSensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER);
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
        long endDate = new Date().getTime();
        int stepCount = (int)sensorEvent.values[0];
        insertData(endDate, stepCount);
    }

    public void insertData(long endDate, int stepCount) {
        if(database != null) {
            SharedPreferences sharedPref = getSharedPreferences("previousStepCount", Context.MODE_PRIVATE);
            int previous = sharedPref.getInt("previousStepCount", 0);

            if(stepCount < previous) {
                previous = 0;
            }

            String latestSelectQuery = "SELECT * FROM steps ORDER BY _id DESC LIMIT 1";
            Cursor cursor = database.rawQuery(latestSelectQuery, null);
            int latestStepCount = 0;

            if (cursor.getCount() > 0) {
                cursor.moveToNext();
                latestStepCount = cursor.getInt(3);
            }

            Log.i(TAG, "latestStepCount: " + latestStepCount);
            Log.i(TAG, "previous: " + previous);
            Log.i(TAG, "stepCount: " + stepCount);

            latestStepCount = latestStepCount + (stepCount - previous);

            SharedPreferences.Editor editor = sharedPref.edit();
            editor.putInt("previousStepCount", stepCount);
            editor.commit();

            String sql = "insert into steps (startDate, endDate, stepCount) values (?, ?, ?)";
            Object[] params = {startDate, endDate, latestStepCount};
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
