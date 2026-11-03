package dev.restage.early

import android.os.SystemClock
import java.net.InetAddress
import java.net.Socket
import javax.net.ssl.HandshakeCompletedEvent
import javax.net.ssl.HandshakeCompletedListener
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/** Timings of one request's network phases, in milliseconds. */
class EarlyPhases {
    private fun now() = SystemClock.elapsedRealtimeNanos()
    private var start = now()
    private var dnsDone = start
    private var tcpDone = 0L
    private var tlsDone = 0L
    private var writeDone = 0L
    private var firstByte = 0L
    private var end = 0L
    @Volatile private var connected = false
    @Volatile private var tlsInfo = ""

    fun resolve(host: String) {
        start = now()
        runCatching { InetAddress.getAllByName(host) }
        dnsDone = now()
    }

    fun wrote() { writeDone = now() }
    fun gotFirstByte() { firstByte = now() }
    fun finished() { end = now() }

    /** Wraps the TLS socket factory so the connection reports when TCP and TLS finish. */
    fun factory(delegate: SSLSocketFactory): SSLSocketFactory = object : SSLSocketFactory() {
        override fun createSocket(s: Socket, host: String, port: Int, autoClose: Boolean): Socket {
            tcpDone = now()
            connected = true
            val socket = delegate.createSocket(s, host, port, autoClose)
            val wallAtConnect = System.currentTimeMillis()
            (socket as? SSLSocket)?.addHandshakeCompletedListener(
                HandshakeCompletedListener { event ->
                    tlsDone = now()
                    tlsInfo = describe(event, wallAtConnect)
                },
            )
            return socket
        }
        override fun createSocket(host: String, port: Int): Socket = delegate.createSocket(host, port)
        override fun createSocket(host: String, port: Int, local: InetAddress, localPort: Int): Socket =
            delegate.createSocket(host, port, local, localPort)
        override fun createSocket(host: InetAddress, port: Int): Socket = delegate.createSocket(host, port)
        override fun createSocket(host: InetAddress, port: Int, local: InetAddress, localPort: Int): Socket =
            delegate.createSocket(host, port, local, localPort)
        override fun getDefaultCipherSuites(): Array<String> = delegate.defaultCipherSuites
        override fun getSupportedCipherSuites(): Array<String> = delegate.supportedCipherSuites
    }

    // A resumed session keeps the creation time of the one it resumes.
    private fun describe(event: HandshakeCompletedEvent, wallAtConnect: Long): String {
        val session = event.session
        val alpn = runCatching { (event.socket as? SSLSocket)?.applicationProtocol }.getOrNull()
        return "protocol=${session.protocol} cipher=${session.cipherSuite} alpn=${alpn.takeUnless { it.isNullOrEmpty() }} " +
            "resumed=${session.creationTime < wallAtConnect - 1000}"
    }

    private fun ms(from: Long, to: Long) = if (from == 0L || to == 0L || to < from) -1 else (to - from) / 1_000_000

    /** One log line: timings, and the TLS parameters negotiated. */
    fun line(): String =
        "phases dns=${ms(start, dnsDone)} tcp=${ms(dnsDone, tcpDone)} tls=${ms(tcpDone, tlsDone)} " +
            "write=${ms(tlsDone, writeDone)} firstbyte=${ms(writeDone, firstByte)} total=${ms(start, end)} ms " +
            "reused=${!connected} $tlsInfo".trimEnd()
}
