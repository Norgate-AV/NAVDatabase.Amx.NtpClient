MODULE_NAME='mNtpClient'    (
                                dev vdvObject,
                                dev dvPort
                            )

(***********************************************************)
#DEFINE USING_NAV_MODULE_BASE_CALLBACKS
#DEFINE USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.SocketUtils.axi'
#include 'NAVFoundation.NtpClient.axi'
#include 'LibNtpClient.axi'

/*
 _   _                       _          ___     __
| \ | | ___  _ __ __ _  __ _| |_ ___   / \ \   / /
|  \| |/ _ \| '__/ _` |/ _` | __/ _ \ / _ \ \ / /
| |\  | (_) | | | (_| | (_| | ||  __// ___ \ V /
|_| \_|\___/|_|  \__, |\__,_|\__\___/_/   \_\_/
                 |___/

MIT License

Copyright (c) 2023 Norgate AV Services Limited

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

(***********************************************************)
(*          DEVICE NUMBER DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_DEVICE

(***********************************************************)
(*               CONSTANT DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_CONSTANT

constant long TL_NAV_NTP_SYNC = 201
constant long TL_NAV_NTP_CLIENT_TIMEOUT = 202


(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE

volatile _NAVNtpClient client


(***********************************************************)
(*               LATCHING DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_LATCHING

(***********************************************************)
(*       MUTUALLY EXCLUSIVE DEFINITIONS GO BELOW           *)
(***********************************************************)
DEFINE_MUTUALLY_EXCLUSIVE

(***********************************************************)
(*        SUBROUTINE/FUNCTION DEFINITIONS GO BELOW         *)
(***********************************************************)
(* EXAMPLE: DEFINE_FUNCTION <RETURN_TYPE> <NAME> (<PARAMETERS>) *)
(* EXAMPLE: DEFINE_CALL '<NAME>' (<PARAMETERS>) *)

define_function SendPacket(_NAVNtpClient client) {
    stack_var char payload[NAV_NTP_PACKET_SIZE]

    if (!client.SocketConnection.IsConnected) {
        return
    }

    payload = NAVGetNtpPacketByteArray(client.Packet)

    NAVErrorLog(NAV_LOG_LEVEL_DEBUG, NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_TO, client.device, payload))
    send_string client.Device, "payload"

    NAVTimelineStart(TL_NAV_NTP_CLIENT_TIMEOUT, client.TimeOut, TIMELINE_ABSOLUTE, TIMELINE_ONCE)
}


define_function ParseResponse(char data[]) {
    stack_var _NAVNtpPacket packet
    stack_var long epoch

    NAVNtpResponseToPacket(data, packet)

    epoch = packet.TransmitTimestampS - NAV_NTP_TIMESTAMP_DELTA

    send_string vdvObject, "'NTP_EPOCH-', itoa(epoch)"
}


define_function SyncEvent(_NAVNtpClient client) {
    if (client.SocketConnection.IsConnected) {
        return
    }

    NAVClientSocketOpen(client.Socket,
                        client.SocketConnection.Address,
                        client.SocketConnection.Port,
                        IP_UDP_2WAY)
}


#IF_DEFINED USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
define_function NAVModulePropertyEventCallback(_NAVModulePropertyEvent event) {
    switch (event.Name) {
        case NAV_MODULE_PROPERTY_EVENT_IP_ADDRESS: {
            client.SocketConnection.Address = event.Args[1]
        }
    }
}
#END_IF


(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {
    NAVNtpClientInit(client, dvPort)
    NAVTimelineStart(TL_NAV_NTP_SYNC, client.SyncInterval, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
}

(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT

data_event[dvPort] {
    online: {
        NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'mNtpClient => Socket Online'")
        client.SocketConnection.IsConnected = true

        SendPacket(client)
    }
    offline: {
        NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'mNtpClient => Socket Offline'")
        client.SocketConnection.IsConnected = false
    }
    onerror: {
        NAVErrorLog(NAV_LOG_LEVEL_ERROR, "'mNtpClient => Socket Error :: ', NAVGetSocketError(type_cast(data.number))")
        client.SocketConnection.IsConnected = false
    }
    string: {
        NAVTimelineStop(TL_NAV_NTP_CLIENT_TIMEOUT)

        NAVClientSocketClose(data.device.port)
        NAVErrorLog(NAV_LOG_LEVEL_DEBUG, NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_FROM, data.device, data.text))

        ParseResponse(data.text)
    }
}


data_event[vdvObject] {
    online: {

    }
    command: {
        stack_var _NAVSnapiMessage message

        NAVParseSnapiMessage(data.text, message)

        switch (message.Header) {
            default: {

            }
        }
    }
}


timeline_event[TL_NAV_NTP_SYNC] {
    SyncEvent(client)
}


timeline_event[TL_NAV_NTP_CLIENT_TIMEOUT] {
    NAVErrorLog(NAV_LOG_LEVEL_WARNING, "'mNtpClient => Socket Connection Timed Out'")
    NAVClientSocketClose(client.Socket)
}


(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)
