/**
 * SerialInputOutputManager - Async IO loop for USB serial communication
 * Ported from usb-serial-for-android SerialInputOutputManager to HarmonyOS ArkTS
 *
 * Key differences:
 * - Java Thread/Runnable replaced with async start() / stop() pattern
 * - Listener callbacks use ArkTS interface (no inner Listener class with anonymous impl)
 * - State is a string union type instead of Android enum
 * - Write buffering uses Uint8Array accumulation
 */
import { IUsbSerialPort } from './IUsbSerial';

const READ_WAIT_MILLIS = 200;
const BUFSIZ = 4096;

export type IOState = 'STOPPED' | 'RUNNING' | 'STOPPING';

/**
 * Implement this interface to receive data and error notifications.
 */
export interface ISerialListener {
  /**
   * Called with newly received raw data bytes.
   */
  onNewData(data: Uint8Array): void;

  /**
   * Called when an error occurs; after this, the IO loop exits.
   */
  onRunError(e: Error): void;
}

/**
 * Continuously reads from and writes to a USB serial port in an async loop.
 *
 * Usage:
 *   const manager = new SerialInputOutputManager(port, listener);
 *   manager.start(); // non-blocking; starts the async loop
 *   manager.writeAsync(data); // queue data to be written
 *   manager.stop(); // request graceful shutdown
 */
export class SerialInputOutputManager {
  private mPort: IUsbSerialPort;
  private mListener: ISerialListener;
  private mState: IOState = 'STOPPED';
  private mWriteBuffer: Uint8Array = new Uint8Array(0);
  private mReadTimeout: number = READ_WAIT_MILLIS;
  private mWriteTimeout: number = 0;

  constructor(serialPort: IUsbSerialPort, listener: ISerialListener) {
    this.mPort = serialPort;
    this.mListener = listener;
  }

  getState(): IOState {
    return this.mState;
  }

  /**
   * Returns whether the IO loop is currently running.
   */
  isRunning(): boolean {
    return this.mState === 'RUNNING';
  }

  /**
   * Queue data to be written on the next IO loop iteration.
   */
  writeAsync(data: Uint8Array): void {
    const merged = new Uint8Array(this.mWriteBuffer.length + data.length);
    merged.set(this.mWriteBuffer, 0);
    merged.set(data, this.mWriteBuffer.length);
    this.mWriteBuffer = merged;
  }

  /**
   * Request the IO loop to stop after the current iteration.
   */
  stop(): void {
    if (this.mState === 'RUNNING') {
      this.mState = 'STOPPING';
    }
  }

  /**
   * Start the async IO loop. Returns immediately; loop runs in the background.
   * Calls listener.onNewData() for each received data chunk.
   * Calls listener.onRunError() if an error occurs then halts.
   */
  start(): void {
    if (this.mState !== 'STOPPED') {
      throw new Error('Already running');
    }
    this.mState = 'RUNNING';
    this.runLoop();
  }

  private runLoop(): void {
    this.step()
      .then(() => {
        if (this.mState === 'RUNNING') {
          this.runLoop();
        } else {
          this.mState = 'STOPPED';
        }
      })
      .catch((e: Error) => {
        this.mState = 'STOPPED';
        this.mListener.onRunError(e);
      });
  }

  private async step(): Promise<void> {
    // Write any buffered data
    if (this.mWriteBuffer.length > 0) {
      const toWrite = this.mWriteBuffer;
      this.mWriteBuffer = new Uint8Array(0);
      const timeout = this.mWriteTimeout > 0 ? this.mWriteTimeout : 1000;
      await this.mPort.write(toWrite, timeout);
    }

    // Read available data
    const dest = new Uint8Array(BUFSIZ);
    const numBytesRead = await this.mPort.read(dest, this.mReadTimeout);
    if (numBytesRead > 0) {
      const data = dest.subarray(0, numBytesRead);
      this.mListener.onNewData(data);
    }
  }

  getReadTimeout(): number {
    return this.mReadTimeout;
  }

  setReadTimeout(timeout: number): void {
    this.mReadTimeout = timeout;
  }

  getWriteTimeout(): number {
    return this.mWriteTimeout;
  }

  setWriteTimeout(timeout: number): void {
    this.mWriteTimeout = timeout;
  }
}
