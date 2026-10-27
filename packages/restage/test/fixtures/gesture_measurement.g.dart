part of 'gesture_bindings_source.dart';

const gestureMeasuredTapBlob =
    "/lJGVwIAAAAAAAAAAgAAAAAAAAAHAAAAAAAAAHJlc3RhZ2ULAAAAAAAAAG1lYXN1cmVtZW50AgAAAAAAAAAHAAAAAAAAAHJlc3RhZ2UEAAAAAAAAAGNvcmUBAAAAAAAAAAcAAAAAAAAAU3VyZmFjZQAAAAAAAAAACRoAAAAAAAAATWVhc3VyZW1lbnRTb3VyY2VQcmVzZW50ZWQDAAAAAAAAAAgAAAAAAAAAY2FycmllcnMFBwAAAAAAAAAENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwuQW11M3IzSFZuSEFQaWlqRk9aaEI5QXdzSFhDR3hONVIENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwuRTQwVnRqTkYzX2N0bGVGUmRzdlJ6RU5jR25jOGphUlEENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwuTWU4aXJrc0RfRmRJR1IxNVpwNW9yZm5nTzlVV0U2bDIENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwuWHhHY1ZoZk05aTN3N1lyemxia2tJQzByS2l3V0o2NHMENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwuclZOajRNaTRoX1MzS1hONVlxYVVMVGRZWFp4cE5BZTMENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwudk1pZWVJa09oc3pLYkxxUDhiSmZ2SXBLM2M0Rm5HOTgENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwud2VuTXVxajFZcnVDRndmbkNvUms3QlZHbGRZMXBaekIFAAAAAAAAAGNoaWxkCQgAAAAAAAAAVGV4dFJpY2gBAAAAAAAAAAgAAAAAAAAAdGV4dFNwYW4HAgAAAAAAAAAKAAAAAAAAAHJlY29nbml6ZXIHDwAAAAAAAAAEAAAAAAAAAGtpbmQEAwAAAAAAAAB0YXASAAAAAAAAAG9uU2Vjb25kYXJ5VGFwRG93bgcDAAAAAAAAAAgAAAAAAAAAY2FwdHVyZXMHAQAAAAAAAAACAAAAAAAAAGMwCwIAAAAAAAAABAcAAAAAAAAAY29udGV4dAQMAAAAAAAAAF9oY2U3MjQxN2FjMAcAAAAAAAAAcHJvZ3JhbQTWAgAAAAAAAHsidmVyc2lvbiI6MSwibm9kZXMiOlt7Im9wIjoiY2FwdHVyZSIsInR5cGUiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiIoZGFydDpjb3JlI1N0cmluZyxkYXJ0OmNvcmUjT2JqZWN0KS0+dm9pZCJ9LCJuYW1lIjoiYzAifSx7Im9wIjoibmF0aXZlLmNhbGwiLCJ0eXBlIjp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiZmx1dHRlci5HZXN0dXJlVGFwRG93bkNhbGxiYWNrIn0sImlucHV0cyI6WzBdLCJ2YWx1ZSI6eyJiaW5kaW5nIjoiX2hhZTYzYWU5YzQ3IiwiY29udHJhY3QiOnsidHlwZSI6Imluc3RhbGxlZC5jYWxsIiwibnVsbGFibGUiOmZhbHNlLCJjYWxsIjp7ImlucHV0cyI6W3sia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiIoZGFydDpjb3JlI1N0cmluZyxkYXJ0OmNvcmUjT2JqZWN0KS0+dm9pZCJ9XSwiY2FwdHVyZXMiOnt9LCJyZXN1bHQiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiJmbHV0dGVyLkdlc3R1cmVUYXBEb3duQ2FsbGJhY2sifSwiaW1wbGVtZW50YXRpb24iOiJhZTYzYWU5YzQ3M2U1ZmZjOTYxNjg2YjYwYzRiYTRkODQwNWFhZTQ1OWZmNGRiZWI4ZDViMjgzYjlhODUxZjZmIn19LCJjYXB0dXJlcyI6e319fV0sInJvb3QiOjEsImNhcHR1cmVzIjp7ImMwIjp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiKGRhcnQ6Y29yZSNTdHJpbmcsZGFydDpjb3JlI09iamVjdCktPnZvaWQifX0sInBhcmFtZXRlcnMiOnt9fQcAAAAAAAAAdmVyc2lvbgIBAAAAAAAAAB0AAAAAAAAAb25TZWNvbmRhcnlUYXBEb3duTWVhc3VyZW1lbnQOHAAAAAAAAABfX3Jlc3RhZ2VfbWVhc3VyZW1lbnRfdGFwX3YxAQAAAAAAAAAeAAAAAAAAAF9fcmVzdGFnZV9tZWFzdXJlbWVudF9yb3V0ZV92MQQ2AAAAAAAAAG1ydjEuWldSblpTNW5aWE4wZFhKbC53ZW5NdXFqMVlydUNGd2ZuQ29SazdCVkdsZFkxcFp6QhAAAAAAAAAAb25TZWNvbmRhcnlUYXBVcAcDAAAAAAAAAAgAAAAAAAAAY2FwdHVyZXMHAQAAAAAAAAACAAAAAAAAAGMwCwIAAAAAAAAABAcAAAAAAAAAY29udGV4dAQMAAAAAAAAAF9oY2U3MjQxN2FjMAcAAAAAAAAAcHJvZ3JhbQTSAgAAAAAAAHsidmVyc2lvbiI6MSwibm9kZXMiOlt7Im9wIjoiY2FwdHVyZSIsInR5cGUiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiIoZGFydDpjb3JlI1N0cmluZyxkYXJ0OmNvcmUjT2JqZWN0KS0+dm9pZCJ9LCJuYW1lIjoiYzAifSx7Im9wIjoibmF0aXZlLmNhbGwiLCJ0eXBlIjp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiZmx1dHRlci5HZXN0dXJlVGFwVXBDYWxsYmFjayJ9LCJpbnB1dHMiOlswXSwidmFsdWUiOnsiYmluZGluZyI6Il9oNGMwNzY3MzczNiIsImNvbnRyYWN0Ijp7InR5cGUiOiJpbnN0YWxsZWQuY2FsbCIsIm51bGxhYmxlIjpmYWxzZSwiY2FsbCI6eyJpbnB1dHMiOlt7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiKGRhcnQ6Y29yZSNTdHJpbmcsZGFydDpjb3JlI09iamVjdCktPnZvaWQifV0sImNhcHR1cmVzIjp7fSwicmVzdWx0Ijp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiZmx1dHRlci5HZXN0dXJlVGFwVXBDYWxsYmFjayJ9LCJpbXBsZW1lbnRhdGlvbiI6IjRjMDc2NzM3MzZlMzYwNjMzZmM3OTM3MzI4M2RlN2Q0NzFjNDg5OTUxMjliOGI5MjY1MDI2OTNkZDY0OGVjMmMifX0sImNhcHR1cmVzIjp7fX19XSwicm9vdCI6MSwiY2FwdHVyZXMiOnsiYzAiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiIoZGFydDpjb3JlI1N0cmluZyxkYXJ0OmNvcmUjT2JqZWN0KS0+dm9pZCJ9fSwicGFyYW1ldGVycyI6e319BwAAAAAAAAB2ZXJzaW9uAgEAAAAAAAAAGwAAAAAAAABvblNlY29uZGFyeVRhcFVwTWVhc3VyZW1lbnQOHAAAAAAAAABfX3Jlc3RhZ2VfbWVhc3VyZW1lbnRfdGFwX3YxAQAAAAAAAAAeAAAAAAAAAF9fcmVzdGFnZV9tZWFzdXJlbWVudF9yb3V0ZV92MQQ2AAAAAAAAAG1ydjEuWldSblpTNW5aWE4wZFhKbC5FNDBWdGpORjNfY3RsZUZSZHN2UnpFTmNHbmM4amFSUQkAAAAAAAAAb25UYXBEb3duBwMAAAAAAAAACAAAAAAAAABjYXB0dXJlcwcBAAAAAAAAAAIAAAAAAAAAYzALAgAAAAAAAAAEBwAAAAAAAABjb250ZXh0BAwAAAAAAAAAX2hjZTcyNDE3YWMwBwAAAAAAAABwcm9ncmFtBNYCAAAAAAAAeyJ2ZXJzaW9uIjoxLCJub2RlcyI6W3sib3AiOiJjYXB0dXJlIiwidHlwZSI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6IihkYXJ0OmNvcmUjU3RyaW5nLGRhcnQ6Y29yZSNPYmplY3QpLT52b2lkIn0sIm5hbWUiOiJjMCJ9LHsib3AiOiJuYXRpdmUuY2FsbCIsInR5cGUiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiJmbHV0dGVyLkdlc3R1cmVUYXBEb3duQ2FsbGJhY2sifSwiaW5wdXRzIjpbMF0sInZhbHVlIjp7ImJpbmRpbmciOiJfaGQ5ZjQyMWNmMmMiLCJjb250cmFjdCI6eyJ0eXBlIjoiaW5zdGFsbGVkLmNhbGwiLCJudWxsYWJsZSI6ZmFsc2UsImNhbGwiOnsiaW5wdXRzIjpbeyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6IihkYXJ0OmNvcmUjU3RyaW5nLGRhcnQ6Y29yZSNPYmplY3QpLT52b2lkIn1dLCJjYXB0dXJlcyI6e30sInJlc3VsdCI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6ImZsdXR0ZXIuR2VzdHVyZVRhcERvd25DYWxsYmFjayJ9LCJpbXBsZW1lbnRhdGlvbiI6ImQ5ZjQyMWNmMmNkYWM1YThkYTc3ZjIwMjc4MzUyODcxMzE1ODVjMmQ2Y2NmNjgwMjU0YjhmYzA5NzY3YzlmNWIifX0sImNhcHR1cmVzIjp7fX19XSwicm9vdCI6MSwiY2FwdHVyZXMiOnsiYzAiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiIoZGFydDpjb3JlI1N0cmluZyxkYXJ0OmNvcmUjT2JqZWN0KS0+dm9pZCJ9fSwicGFyYW1ldGVycyI6e319BwAAAAAAAAB2ZXJzaW9uAgEAAAAAAAAAFAAAAAAAAABvblRhcERvd25NZWFzdXJlbWVudA4cAAAAAAAAAF9fcmVzdGFnZV9tZWFzdXJlbWVudF90YXBfdjEBAAAAAAAAAB4AAAAAAAAAX19yZXN0YWdlX21lYXN1cmVtZW50X3JvdXRlX3YxBDYAAAAAAAAAbXJ2MS5aV1JuWlM1blpYTjBkWEpsLnJWTmo0TWk0aF9TM0tYTjVZcWFVTFRkWVhaeHBOQWUzCQAAAAAAAABvblRhcE1vdmUHAwAAAAAAAAAIAAAAAAAAAGNhcHR1cmVzBwEAAAAAAAAAAgAAAAAAAABjMAsCAAAAAAAAAAQHAAAAAAAAAGNvbnRleHQEDAAAAAAAAABfaGNlNzI0MTdhYzAHAAAAAAAAAHByb2dyYW0E1gIAAAAAAAB7InZlcnNpb24iOjEsIm5vZGVzIjpbeyJvcCI6ImNhcHR1cmUiLCJ0eXBlIjp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiKGRhcnQ6Y29yZSNTdHJpbmcsZGFydDpjb3JlI09iamVjdCktPnZvaWQifSwibmFtZSI6ImMwIn0seyJvcCI6Im5hdGl2ZS5jYWxsIiwidHlwZSI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6ImZsdXR0ZXIuR2VzdHVyZVRhcE1vdmVDYWxsYmFjayJ9LCJpbnB1dHMiOlswXSwidmFsdWUiOnsiYmluZGluZyI6Il9oYTg2ODU4NTc0MyIsImNvbnRyYWN0Ijp7InR5cGUiOiJpbnN0YWxsZWQuY2FsbCIsIm51bGxhYmxlIjpmYWxzZSwiY2FsbCI6eyJpbnB1dHMiOlt7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiKGRhcnQ6Y29yZSNTdHJpbmcsZGFydDpjb3JlI09iamVjdCktPnZvaWQifV0sImNhcHR1cmVzIjp7fSwicmVzdWx0Ijp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiZmx1dHRlci5HZXN0dXJlVGFwTW92ZUNhbGxiYWNrIn0sImltcGxlbWVudGF0aW9uIjoiYTg2ODU4NTc0M2IyZWRmZjQ0NDZhNGFhM2QxNGUwMTIwMjJhMTBkZjBjM2IyMWQ5MWM5ODMzNmM2ZmJlNDk1NSJ9fSwiY2FwdHVyZXMiOnt9fX1dLCJyb290IjoxLCJjYXB0dXJlcyI6eyJjMCI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6IihkYXJ0OmNvcmUjU3RyaW5nLGRhcnQ6Y29yZSNPYmplY3QpLT52b2lkIn19LCJwYXJhbWV0ZXJzIjp7fX0HAAAAAAAAAHZlcnNpb24CAQAAAAAAAAAUAAAAAAAAAG9uVGFwTW92ZU1lYXN1cmVtZW50DhwAAAAAAAAAX19yZXN0YWdlX21lYXN1cmVtZW50X3RhcF92MQEAAAAAAAAAHgAAAAAAAABfX3Jlc3RhZ2VfbWVhc3VyZW1lbnRfcm91dGVfdjEENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwuTWU4aXJrc0RfRmRJR1IxNVpwNW9yZm5nTzlVV0U2bDIHAAAAAAAAAG9uVGFwVXALAgAAAAAAAAAEBwAAAAAAAABjb250ZXh0BAwAAAAAAAAAX2gwZTliN2U0M2RlEgAAAAAAAABvblRhcFVwTWVhc3VyZW1lbnQOHAAAAAAAAABfX3Jlc3RhZ2VfbWVhc3VyZW1lbnRfdGFwX3YxAQAAAAAAAAAeAAAAAAAAAF9fcmVzdGFnZV9tZWFzdXJlbWVudF9yb3V0ZV92MQQ2AAAAAAAAAG1ydjEuWldSblpTNW5aWE4wZFhKbC5YeEdjVmhmTTlpM3c3WXJ6bGJra0lDMHJLaXdXSjY0cxEAAAAAAAAAb25UZXJ0aWFyeVRhcERvd24HAwAAAAAAAAAIAAAAAAAAAGNhcHR1cmVzBwEAAAAAAAAAAgAAAAAAAABjMAsCAAAAAAAAAAQHAAAAAAAAAGNvbnRleHQEDAAAAAAAAABfaGNlNzI0MTdhYzAHAAAAAAAAAHByb2dyYW0E1gIAAAAAAAB7InZlcnNpb24iOjEsIm5vZGVzIjpbeyJvcCI6ImNhcHR1cmUiLCJ0eXBlIjp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiKGRhcnQ6Y29yZSNTdHJpbmcsZGFydDpjb3JlI09iamVjdCktPnZvaWQifSwibmFtZSI6ImMwIn0seyJvcCI6Im5hdGl2ZS5jYWxsIiwidHlwZSI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6ImZsdXR0ZXIuR2VzdHVyZVRhcERvd25DYWxsYmFjayJ9LCJpbnB1dHMiOlswXSwidmFsdWUiOnsiYmluZGluZyI6Il9oNDk0ZGYwM2IzNyIsImNvbnRyYWN0Ijp7InR5cGUiOiJpbnN0YWxsZWQuY2FsbCIsIm51bGxhYmxlIjpmYWxzZSwiY2FsbCI6eyJpbnB1dHMiOlt7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiKGRhcnQ6Y29yZSNTdHJpbmcsZGFydDpjb3JlI09iamVjdCktPnZvaWQifV0sImNhcHR1cmVzIjp7fSwicmVzdWx0Ijp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiZmx1dHRlci5HZXN0dXJlVGFwRG93bkNhbGxiYWNrIn0sImltcGxlbWVudGF0aW9uIjoiNDk0ZGYwM2IzN2E1ODM5MGIwNTIwOTgzZjZjOTY4MGQ3YmIzYzU3NmY0YmRmYmUzNDBmMDRiOGQ3MmYxOTNjZiJ9fSwiY2FwdHVyZXMiOnt9fX1dLCJyb290IjoxLCJjYXB0dXJlcyI6eyJjMCI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6IihkYXJ0OmNvcmUjU3RyaW5nLGRhcnQ6Y29yZSNPYmplY3QpLT52b2lkIn19LCJwYXJhbWV0ZXJzIjp7fX0HAAAAAAAAAHZlcnNpb24CAQAAAAAAAAAcAAAAAAAAAG9uVGVydGlhcnlUYXBEb3duTWVhc3VyZW1lbnQOHAAAAAAAAABfX3Jlc3RhZ2VfbWVhc3VyZW1lbnRfdGFwX3YxAQAAAAAAAAAeAAAAAAAAAF9fcmVzdGFnZV9tZWFzdXJlbWVudF9yb3V0ZV92MQQ2AAAAAAAAAG1ydjEuWldSblpTNW5aWE4wZFhKbC5BbXUzcjNIVm5IQVBpaWpGT1poQjlBd3NIWENHeE41Ug8AAAAAAAAAb25UZXJ0aWFyeVRhcFVwBwMAAAAAAAAACAAAAAAAAABjYXB0dXJlcwcBAAAAAAAAAAIAAAAAAAAAYzALAgAAAAAAAAAEBwAAAAAAAABjb250ZXh0BAwAAAAAAAAAX2hjZTcyNDE3YWMwBwAAAAAAAABwcm9ncmFtBNICAAAAAAAAeyJ2ZXJzaW9uIjoxLCJub2RlcyI6W3sib3AiOiJjYXB0dXJlIiwidHlwZSI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6IihkYXJ0OmNvcmUjU3RyaW5nLGRhcnQ6Y29yZSNPYmplY3QpLT52b2lkIn0sIm5hbWUiOiJjMCJ9LHsib3AiOiJuYXRpdmUuY2FsbCIsInR5cGUiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiJmbHV0dGVyLkdlc3R1cmVUYXBVcENhbGxiYWNrIn0sImlucHV0cyI6WzBdLCJ2YWx1ZSI6eyJiaW5kaW5nIjoiX2gyMzdiZTFhNjlmIiwiY29udHJhY3QiOnsidHlwZSI6Imluc3RhbGxlZC5jYWxsIiwibnVsbGFibGUiOmZhbHNlLCJjYWxsIjp7ImlucHV0cyI6W3sia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiIoZGFydDpjb3JlI1N0cmluZyxkYXJ0OmNvcmUjT2JqZWN0KS0+dm9pZCJ9XSwiY2FwdHVyZXMiOnt9LCJyZXN1bHQiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiJmbHV0dGVyLkdlc3R1cmVUYXBVcENhbGxiYWNrIn0sImltcGxlbWVudGF0aW9uIjoiMjM3YmUxYTY5ZmU1MWNlMzU1YjhhZDVhZGQ0NGVjYmQwNjk4MmI0NDNiOWNjODliOGY1N2ZlOGI2YjFhMTQ4NyJ9fSwiY2FwdHVyZXMiOnt9fX1dLCJyb290IjoxLCJjYXB0dXJlcyI6eyJjMCI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6IihkYXJ0OmNvcmUjU3RyaW5nLGRhcnQ6Y29yZSNPYmplY3QpLT52b2lkIn19LCJwYXJhbWV0ZXJzIjp7fX0HAAAAAAAAAHZlcnNpb24CAQAAAAAAAAAaAAAAAAAAAG9uVGVydGlhcnlUYXBVcE1lYXN1cmVtZW50DhwAAAAAAAAAX19yZXN0YWdlX21lYXN1cmVtZW50X3RhcF92MQEAAAAAAAAAHgAAAAAAAABfX3Jlc3RhZ2VfbWVhc3VyZW1lbnRfcm91dGVfdjEENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwudk1pZWVJa09oc3pLYkxxUDhiSmZ2SXBLM2M0Rm5HOTgEAAAAAAAAAHRleHQEAwAAAAAAAABUYXALAAAAAAAAAHBvaW50VG9rZW5zBQcAAAAAAAAABCAAAAAAAAAAQW11M3IzSFZuSEFQaWlqRk9aaEI5QXdzSFhDR3hONVIEIAAAAAAAAABFNDBWdGpORjNfY3RsZUZSZHN2UnpFTmNHbmM4amFSUQQgAAAAAAAAAE1lOGlya3NEX0ZkSUdSMTVacDVvcmZuZ085VVdFNmwyBCAAAAAAAAAAWHhHY1ZoZk05aTN3N1lyemxia2tJQzByS2l3V0o2NHMEIAAAAAAAAAByVk5qNE1pNGhfUzNLWE41WXFhVUxUZFlYWnhwTkFlMwQgAAAAAAAAAHZNaWVlSWtPaHN6S2JMcVA4YkpmdklwSzNjNEZuRzk4BCAAAAAAAAAAd2VuTXVxajFZcnVDRndmbkNvUms3QlZHbGRZMXBaekI=";
Map<String, r.NativeBinding<Object?>> gestureMeasuredTapBindings(
        GestureTapScreen source) =>
    {
      "_h0e9b7e43de": r.NativeBinding(
          contract: s.NativeBindingContract(
              type: 'flutter.GestureTapUpCallback', nullable: false),
          value: source.up),
      "_h237be1a69f": r.NativeBinding(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType": "(dart:core#String,dart:core#Object)->void"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "flutter.GestureTapUpCallback"
              },
              "implementation":
                  "237be1a69fe51ce355b8ad5add44ecbd06982b443b9cc89b8f57fe8b6b1a1487"
            }
          }),
          value: r.NativeCallAdapter(
              s.NativeBindingContract.fromJson(<String, Object?>{
                "type": "installed.call",
                "nullable": false,
                "call": <String, Object?>{
                  "inputs": <Object?>[
                    <String, Object?>{
                      "kind": "native",
                      "nativeType": "(dart:core#String,dart:core#Object)->void"
                    }
                  ],
                  "captures": <String, Object?>{},
                  "result": <String, Object?>{
                    "kind": "native",
                    "nativeType": "flutter.GestureTapUpCallback"
                  },
                  "implementation":
                      "237be1a69fe51ce355b8ad5add44ecbd06982b443b9cc89b8f57fe8b6b1a1487"
                }
              }), (_restageInputs, _restageCells) {
            T _restageAs<T>(Object? value) => value as T;
            final void Function(String, Object) _restageInput0 =
                _restageAs<void Function(String, Object)>(
                    (_restageInputs[0] as s.ValueNative).value);
            final void Function(f.TapUpDetails) _restageResult =
                (details) => _restageInput0('tertiary.up', details);
            return r.NativeBinding<void Function(f.TapUpDetails)>(
                contract: s.NativeBindingContract(
                    type: "flutter.GestureTapUpCallback", nullable: false),
                value: _restageResult);
          })),
      "_h494df03b37": r.NativeBinding(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType": "(dart:core#String,dart:core#Object)->void"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "flutter.GestureTapDownCallback"
              },
              "implementation":
                  "494df03b37a58390b0520983f6c9680d7bb3c576f4bdfbe340f04b8d72f193cf"
            }
          }),
          value: r.NativeCallAdapter(
              s.NativeBindingContract.fromJson(<String, Object?>{
                "type": "installed.call",
                "nullable": false,
                "call": <String, Object?>{
                  "inputs": <Object?>[
                    <String, Object?>{
                      "kind": "native",
                      "nativeType": "(dart:core#String,dart:core#Object)->void"
                    }
                  ],
                  "captures": <String, Object?>{},
                  "result": <String, Object?>{
                    "kind": "native",
                    "nativeType": "flutter.GestureTapDownCallback"
                  },
                  "implementation":
                      "494df03b37a58390b0520983f6c9680d7bb3c576f4bdfbe340f04b8d72f193cf"
                }
              }), (_restageInputs, _restageCells) {
            T _restageAs<T>(Object? value) => value as T;
            final void Function(String, Object) _restageInput0 =
                _restageAs<void Function(String, Object)>(
                    (_restageInputs[0] as s.ValueNative).value);
            final void Function(f.TapDownDetails) _restageResult =
                (details) => _restageInput0('tertiary.down', details);
            return r.NativeBinding<void Function(f.TapDownDetails)>(
                contract: s.NativeBindingContract(
                    type: "flutter.GestureTapDownCallback", nullable: false),
                value: _restageResult);
          })),
      "_h4c07673736": r.NativeBinding(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType": "(dart:core#String,dart:core#Object)->void"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "flutter.GestureTapUpCallback"
              },
              "implementation":
                  "4c07673736e360633fc79373283de7d471c48995129b8b926502693dd648ec2c"
            }
          }),
          value: r.NativeCallAdapter(
              s.NativeBindingContract.fromJson(<String, Object?>{
                "type": "installed.call",
                "nullable": false,
                "call": <String, Object?>{
                  "inputs": <Object?>[
                    <String, Object?>{
                      "kind": "native",
                      "nativeType": "(dart:core#String,dart:core#Object)->void"
                    }
                  ],
                  "captures": <String, Object?>{},
                  "result": <String, Object?>{
                    "kind": "native",
                    "nativeType": "flutter.GestureTapUpCallback"
                  },
                  "implementation":
                      "4c07673736e360633fc79373283de7d471c48995129b8b926502693dd648ec2c"
                }
              }), (_restageInputs, _restageCells) {
            T _restageAs<T>(Object? value) => value as T;
            final void Function(String, Object) _restageInput0 =
                _restageAs<void Function(String, Object)>(
                    (_restageInputs[0] as s.ValueNative).value);
            final void Function(f.TapUpDetails) _restageResult =
                (details) => _restageInput0('secondary.up', details);
            return r.NativeBinding<void Function(f.TapUpDetails)>(
                contract: s.NativeBindingContract(
                    type: "flutter.GestureTapUpCallback", nullable: false),
                value: _restageResult);
          })),
      "_ha868585743": r.NativeBinding(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType": "(dart:core#String,dart:core#Object)->void"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "flutter.GestureTapMoveCallback"
              },
              "implementation":
                  "a868585743b2edff4446a4aa3d14e012022a10df0c3b21d91c98336c6fbe4955"
            }
          }),
          value: r.NativeCallAdapter(
              s.NativeBindingContract.fromJson(<String, Object?>{
                "type": "installed.call",
                "nullable": false,
                "call": <String, Object?>{
                  "inputs": <Object?>[
                    <String, Object?>{
                      "kind": "native",
                      "nativeType": "(dart:core#String,dart:core#Object)->void"
                    }
                  ],
                  "captures": <String, Object?>{},
                  "result": <String, Object?>{
                    "kind": "native",
                    "nativeType": "flutter.GestureTapMoveCallback"
                  },
                  "implementation":
                      "a868585743b2edff4446a4aa3d14e012022a10df0c3b21d91c98336c6fbe4955"
                }
              }), (_restageInputs, _restageCells) {
            T _restageAs<T>(Object? value) => value as T;
            final void Function(String, Object) _restageInput0 =
                _restageAs<void Function(String, Object)>(
                    (_restageInputs[0] as s.ValueNative).value);
            final void Function(g.TapMoveDetails) _restageResult =
                (details) => _restageInput0('move', details);
            return r.NativeBinding<void Function(g.TapMoveDetails)>(
                contract: s.NativeBindingContract(
                    type: "flutter.GestureTapMoveCallback", nullable: false),
                value: _restageResult);
          })),
      "_hae63ae9c47": r.NativeBinding(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType": "(dart:core#String,dart:core#Object)->void"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "flutter.GestureTapDownCallback"
              },
              "implementation":
                  "ae63ae9c473e5ffc961686b60c4ba4d8405aae459ff4dbeb8d5b283b9a851f6f"
            }
          }),
          value: r.NativeCallAdapter(
              s.NativeBindingContract.fromJson(<String, Object?>{
                "type": "installed.call",
                "nullable": false,
                "call": <String, Object?>{
                  "inputs": <Object?>[
                    <String, Object?>{
                      "kind": "native",
                      "nativeType": "(dart:core#String,dart:core#Object)->void"
                    }
                  ],
                  "captures": <String, Object?>{},
                  "result": <String, Object?>{
                    "kind": "native",
                    "nativeType": "flutter.GestureTapDownCallback"
                  },
                  "implementation":
                      "ae63ae9c473e5ffc961686b60c4ba4d8405aae459ff4dbeb8d5b283b9a851f6f"
                }
              }), (_restageInputs, _restageCells) {
            T _restageAs<T>(Object? value) => value as T;
            final void Function(String, Object) _restageInput0 =
                _restageAs<void Function(String, Object)>(
                    (_restageInputs[0] as s.ValueNative).value);
            final void Function(f.TapDownDetails) _restageResult =
                (details) => _restageInput0('secondary.down', details);
            return r.NativeBinding<void Function(f.TapDownDetails)>(
                contract: s.NativeBindingContract(
                    type: "flutter.GestureTapDownCallback", nullable: false),
                value: _restageResult);
          })),
      "_hce72417ac0": r.NativeBinding(
          contract: s.NativeBindingContract(
              type: '(dart:core#String,dart:core#Object)->void',
              nullable: false),
          value: source.seen),
      "_hd9f421cf2c": r.NativeBinding(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType": "(dart:core#String,dart:core#Object)->void"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "flutter.GestureTapDownCallback"
              },
              "implementation":
                  "d9f421cf2cdac5a8da77f2027835287131585c2d6ccf680254b8fc09767c9f5b"
            }
          }),
          value: r.NativeCallAdapter(
              s.NativeBindingContract.fromJson(<String, Object?>{
                "type": "installed.call",
                "nullable": false,
                "call": <String, Object?>{
                  "inputs": <Object?>[
                    <String, Object?>{
                      "kind": "native",
                      "nativeType": "(dart:core#String,dart:core#Object)->void"
                    }
                  ],
                  "captures": <String, Object?>{},
                  "result": <String, Object?>{
                    "kind": "native",
                    "nativeType": "flutter.GestureTapDownCallback"
                  },
                  "implementation":
                      "d9f421cf2cdac5a8da77f2027835287131585c2d6ccf680254b8fc09767c9f5b"
                }
              }), (_restageInputs, _restageCells) {
            T _restageAs<T>(Object? value) => value as T;
            final void Function(String, Object) _restageInput0 =
                _restageAs<void Function(String, Object)>(
                    (_restageInputs[0] as s.ValueNative).value);
            final void Function(f.TapDownDetails) _restageResult =
                (details) => _restageInput0('down', details);
            return r.NativeBinding<void Function(f.TapDownDetails)>(
                contract: s.NativeBindingContract(
                    type: "flutter.GestureTapDownCallback", nullable: false),
                value: _restageResult);
          })),
    };
Map<String, Object?> gestureMeasuredTapContext() => {
      "_h0e9b7e43de": {
        "kind": "nativeBinding",
        "key": "_h0e9b7e43de",
        "type": "flutter.GestureTapUpCallback",
        "nullable": false
      },
      "_h237be1a69f": {
        "kind": "nativeBinding",
        "key": "_h237be1a69f",
        "type": "installed.call",
        "nullable": false
      },
      "_h494df03b37": {
        "kind": "nativeBinding",
        "key": "_h494df03b37",
        "type": "installed.call",
        "nullable": false
      },
      "_h4c07673736": {
        "kind": "nativeBinding",
        "key": "_h4c07673736",
        "type": "installed.call",
        "nullable": false
      },
      "_ha868585743": {
        "kind": "nativeBinding",
        "key": "_ha868585743",
        "type": "installed.call",
        "nullable": false
      },
      "_hae63ae9c47": {
        "kind": "nativeBinding",
        "key": "_hae63ae9c47",
        "type": "installed.call",
        "nullable": false
      },
      "_hce72417ac0": {
        "kind": "nativeBinding",
        "key": "_hce72417ac0",
        "type": "(dart:core#String,dart:core#Object)->void",
        "nullable": false
      },
      "_hd9f421cf2c": {
        "kind": "nativeBinding",
        "key": "_hd9f421cf2c",
        "type": "installed.call",
        "nullable": false
      }
    };
const Map<String, String> gestureMeasuredTapRoutes = {
  "onSecondaryTapDown":
      "mrv1.ZWRnZS5nZXN0dXJl.wenMuqj1YruCFwfnCoRk7BVGldY1pZzB",
  "onSecondaryTapUp": "mrv1.ZWRnZS5nZXN0dXJl.E40VtjNF3_ctleFRdsvRzENcGnc8jaRQ",
  "onTapDown": "mrv1.ZWRnZS5nZXN0dXJl.rVNj4Mi4h_S3KXN5YqaULTdYXZxpNAe3",
  "onTapMove": "mrv1.ZWRnZS5nZXN0dXJl.Me8irksD_FdIGR15Zp5orfngO9UWE6l2",
  "onTapUp": "mrv1.ZWRnZS5nZXN0dXJl.XxGcVhfM9i3w7YrzlbkkIC0rKiwWJ64s",
  "onTertiaryTapDown": "mrv1.ZWRnZS5nZXN0dXJl.Amu3r3HVnHAPiijFOZhB9AwsHXCGxN5R",
  "onTertiaryTapUp": "mrv1.ZWRnZS5nZXN0dXJl.vMieeIkOhszKbLqP8bJfvIpK3c4FnG98"
};
const gestureMeasuredBorrowedBlob =
    "/lJGVwEAAAAAAAAAAgAAAAAAAAAHAAAAAAAAAHJlc3RhZ2UEAAAAAAAAAGNvcmUBAAAAAAAAAAcAAAAAAAAAU3VyZmFjZQAAAAAAAAAACQgAAAAAAAAAVGV4dFJpY2gBAAAAAAAAAAgAAAAAAAAAdGV4dFNwYW4HAQAAAAAAAAAIAAAAAAAAAGNoaWxkcmVuBQIAAAAAAAAABwIAAAAAAAAACgAAAAAAAAByZWNvZ25pemVyBwEAAAAAAAAACAAAAAAAAABib3Jyb3dlZAsCAAAAAAAAAAQHAAAAAAAAAGNvbnRleHQEDAAAAAAAAABfaGY5Yjg3YTNiNzgEAAAAAAAAAHRleHQEBQAAAAAAAABGaXJzdAcCAAAAAAAAAAoAAAAAAAAAcmVjb2duaXplcgcBAAAAAAAAAAgAAAAAAAAAYm9ycm93ZWQLAgAAAAAAAAAEBwAAAAAAAABjb250ZXh0BAwAAAAAAAAAX2hmOWI4N2EzYjc4BAAAAAAAAAB0ZXh0BAYAAAAAAAAAU2Vjb25k";
Map<String, r.NativeBinding<Object?>> gestureMeasuredBorrowedBindings(
        GestureBorrowedScreen source) =>
    {
      "_hf9b87a3b78": r.NativeBinding(
          contract: s.NativeBindingContract(
              type: 'flutter.GestureRecognizer', nullable: false),
          value: source.recognizer),
    };
Map<String, Object?> gestureMeasuredBorrowedContext() => {
      "_hf9b87a3b78": {
        "kind": "nativeBinding",
        "key": "_hf9b87a3b78",
        "type": "flutter.GestureRecognizer",
        "nullable": false
      }
    };
const Map<String, String> gestureMeasuredBorrowedRoutes = {};
