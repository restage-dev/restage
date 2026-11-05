part of 'gesture_bindings_source.dart';

const gestureMeasuredTapBlob =
    "/lJGVwIAAAAAAAAAAgAAAAAAAAAHAAAAAAAAAHJlc3RhZ2ULAAAAAAAAAG1lYXN1cmVtZW50AgAAAAAAAAAHAAAAAAAAAHJlc3RhZ2UEAAAAAAAAAGNvcmUBAAAAAAAAAAcAAAAAAAAAU3VyZmFjZQAAAAAAAAAACRoAAAAAAAAATWVhc3VyZW1lbnRTb3VyY2VQcmVzZW50ZWQDAAAAAAAAAAgAAAAAAAAAY2FycmllcnMFBwAAAAAAAAAENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwuQW11M3IzSFZuSEFQaWlqRk9aaEI5QXdzSFhDR3hONVIENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwuRTQwVnRqTkYzX2N0bGVGUmRzdlJ6RU5jR25jOGphUlEENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwuTWU4aXJrc0RfRmRJR1IxNVpwNW9yZm5nTzlVV0U2bDIENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwuWHhHY1ZoZk05aTN3N1lyemxia2tJQzByS2l3V0o2NHMENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwuclZOajRNaTRoX1MzS1hONVlxYVVMVGRZWFp4cE5BZTMENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwudk1pZWVJa09oc3pLYkxxUDhiSmZ2SXBLM2M0Rm5HOTgENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwud2VuTXVxajFZcnVDRndmbkNvUms3QlZHbGRZMXBaekIFAAAAAAAAAGNoaWxkCQgAAAAAAAAAVGV4dFJpY2gBAAAAAAAAAAgAAAAAAAAAdGV4dFNwYW4HAgAAAAAAAAAKAAAAAAAAAHJlY29nbml6ZXIHDwAAAAAAAAAEAAAAAAAAAGtpbmQEAwAAAAAAAAB0YXASAAAAAAAAAG9uU2Vjb25kYXJ5VGFwRG93bgcDAAAAAAAAAAgAAAAAAAAAY2FwdHVyZXMHAQAAAAAAAAACAAAAAAAAAGMwCwIAAAAAAAAABAcAAAAAAAAAY29udGV4dAQMAAAAAAAAAF9oY2U3MjQxN2FjMAcAAAAAAAAAcHJvZ3JhbQTWAgAAAAAAAHsidmVyc2lvbiI6MSwibm9kZXMiOlt7Im9wIjoiY2FwdHVyZSIsInR5cGUiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiIoZGFydDpjb3JlI1N0cmluZyxkYXJ0OmNvcmUjT2JqZWN0KS0+dm9pZCJ9LCJuYW1lIjoiYzAifSx7Im9wIjoibmF0aXZlLmNhbGwiLCJ0eXBlIjp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiZmx1dHRlci5HZXN0dXJlVGFwRG93bkNhbGxiYWNrIn0sImlucHV0cyI6WzBdLCJ2YWx1ZSI6eyJiaW5kaW5nIjoiX2g0OWE0MzQxMzI0IiwiY29udHJhY3QiOnsidHlwZSI6Imluc3RhbGxlZC5jYWxsIiwibnVsbGFibGUiOmZhbHNlLCJjYWxsIjp7ImlucHV0cyI6W3sia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiIoZGFydDpjb3JlI1N0cmluZyxkYXJ0OmNvcmUjT2JqZWN0KS0+dm9pZCJ9XSwiY2FwdHVyZXMiOnt9LCJyZXN1bHQiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiJmbHV0dGVyLkdlc3R1cmVUYXBEb3duQ2FsbGJhY2sifSwiaW1wbGVtZW50YXRpb24iOiI0OWE0MzQxMzI0YmMxYjA4Y2VkMTliYTgwYmNjNjFhNTUyMmIzOTYyNmNkYThjNmMwYjBjZGQzZjUwOTVlMTM5In19LCJjYXB0dXJlcyI6e319fV0sInJvb3QiOjEsImNhcHR1cmVzIjp7ImMwIjp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiKGRhcnQ6Y29yZSNTdHJpbmcsZGFydDpjb3JlI09iamVjdCktPnZvaWQifX0sInBhcmFtZXRlcnMiOnt9fQcAAAAAAAAAdmVyc2lvbgIBAAAAAAAAAB0AAAAAAAAAb25TZWNvbmRhcnlUYXBEb3duTWVhc3VyZW1lbnQOHAAAAAAAAABfX3Jlc3RhZ2VfbWVhc3VyZW1lbnRfdGFwX3YxAQAAAAAAAAAeAAAAAAAAAF9fcmVzdGFnZV9tZWFzdXJlbWVudF9yb3V0ZV92MQQ2AAAAAAAAAG1ydjEuWldSblpTNW5aWE4wZFhKbC53ZW5NdXFqMVlydUNGd2ZuQ29SazdCVkdsZFkxcFp6QhAAAAAAAAAAb25TZWNvbmRhcnlUYXBVcAcDAAAAAAAAAAgAAAAAAAAAY2FwdHVyZXMHAQAAAAAAAAACAAAAAAAAAGMwCwIAAAAAAAAABAcAAAAAAAAAY29udGV4dAQMAAAAAAAAAF9oY2U3MjQxN2FjMAcAAAAAAAAAcHJvZ3JhbQTSAgAAAAAAAHsidmVyc2lvbiI6MSwibm9kZXMiOlt7Im9wIjoiY2FwdHVyZSIsInR5cGUiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiIoZGFydDpjb3JlI1N0cmluZyxkYXJ0OmNvcmUjT2JqZWN0KS0+dm9pZCJ9LCJuYW1lIjoiYzAifSx7Im9wIjoibmF0aXZlLmNhbGwiLCJ0eXBlIjp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiZmx1dHRlci5HZXN0dXJlVGFwVXBDYWxsYmFjayJ9LCJpbnB1dHMiOlswXSwidmFsdWUiOnsiYmluZGluZyI6Il9oZTNiMTBiNjk0NSIsImNvbnRyYWN0Ijp7InR5cGUiOiJpbnN0YWxsZWQuY2FsbCIsIm51bGxhYmxlIjpmYWxzZSwiY2FsbCI6eyJpbnB1dHMiOlt7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiKGRhcnQ6Y29yZSNTdHJpbmcsZGFydDpjb3JlI09iamVjdCktPnZvaWQifV0sImNhcHR1cmVzIjp7fSwicmVzdWx0Ijp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiZmx1dHRlci5HZXN0dXJlVGFwVXBDYWxsYmFjayJ9LCJpbXBsZW1lbnRhdGlvbiI6ImUzYjEwYjY5NDVlMjc1MjllMzY5MTZhYTBiMDFmZjA1Y2NlNjEzN2ZmMjEwYzIwODllMjVjNzk4ZmY5MDhlOTcifX0sImNhcHR1cmVzIjp7fX19XSwicm9vdCI6MSwiY2FwdHVyZXMiOnsiYzAiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiIoZGFydDpjb3JlI1N0cmluZyxkYXJ0OmNvcmUjT2JqZWN0KS0+dm9pZCJ9fSwicGFyYW1ldGVycyI6e319BwAAAAAAAAB2ZXJzaW9uAgEAAAAAAAAAGwAAAAAAAABvblNlY29uZGFyeVRhcFVwTWVhc3VyZW1lbnQOHAAAAAAAAABfX3Jlc3RhZ2VfbWVhc3VyZW1lbnRfdGFwX3YxAQAAAAAAAAAeAAAAAAAAAF9fcmVzdGFnZV9tZWFzdXJlbWVudF9yb3V0ZV92MQQ2AAAAAAAAAG1ydjEuWldSblpTNW5aWE4wZFhKbC5FNDBWdGpORjNfY3RsZUZSZHN2UnpFTmNHbmM4amFSUQkAAAAAAAAAb25UYXBEb3duBwMAAAAAAAAACAAAAAAAAABjYXB0dXJlcwcBAAAAAAAAAAIAAAAAAAAAYzALAgAAAAAAAAAEBwAAAAAAAABjb250ZXh0BAwAAAAAAAAAX2hjZTcyNDE3YWMwBwAAAAAAAABwcm9ncmFtBNYCAAAAAAAAeyJ2ZXJzaW9uIjoxLCJub2RlcyI6W3sib3AiOiJjYXB0dXJlIiwidHlwZSI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6IihkYXJ0OmNvcmUjU3RyaW5nLGRhcnQ6Y29yZSNPYmplY3QpLT52b2lkIn0sIm5hbWUiOiJjMCJ9LHsib3AiOiJuYXRpdmUuY2FsbCIsInR5cGUiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiJmbHV0dGVyLkdlc3R1cmVUYXBEb3duQ2FsbGJhY2sifSwiaW5wdXRzIjpbMF0sInZhbHVlIjp7ImJpbmRpbmciOiJfaDA1MDk3MmI3ZmEiLCJjb250cmFjdCI6eyJ0eXBlIjoiaW5zdGFsbGVkLmNhbGwiLCJudWxsYWJsZSI6ZmFsc2UsImNhbGwiOnsiaW5wdXRzIjpbeyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6IihkYXJ0OmNvcmUjU3RyaW5nLGRhcnQ6Y29yZSNPYmplY3QpLT52b2lkIn1dLCJjYXB0dXJlcyI6e30sInJlc3VsdCI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6ImZsdXR0ZXIuR2VzdHVyZVRhcERvd25DYWxsYmFjayJ9LCJpbXBsZW1lbnRhdGlvbiI6IjA1MDk3MmI3ZmEzODljNzRmYTY0N2Q3ZDNlYTY2ZTE0OTVlOWJmOTJhNzVhNGYzM2UyY2M5MWZmY2JhZmNiMTEifX0sImNhcHR1cmVzIjp7fX19XSwicm9vdCI6MSwiY2FwdHVyZXMiOnsiYzAiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiIoZGFydDpjb3JlI1N0cmluZyxkYXJ0OmNvcmUjT2JqZWN0KS0+dm9pZCJ9fSwicGFyYW1ldGVycyI6e319BwAAAAAAAAB2ZXJzaW9uAgEAAAAAAAAAFAAAAAAAAABvblRhcERvd25NZWFzdXJlbWVudA4cAAAAAAAAAF9fcmVzdGFnZV9tZWFzdXJlbWVudF90YXBfdjEBAAAAAAAAAB4AAAAAAAAAX19yZXN0YWdlX21lYXN1cmVtZW50X3JvdXRlX3YxBDYAAAAAAAAAbXJ2MS5aV1JuWlM1blpYTjBkWEpsLnJWTmo0TWk0aF9TM0tYTjVZcWFVTFRkWVhaeHBOQWUzCQAAAAAAAABvblRhcE1vdmUHAwAAAAAAAAAIAAAAAAAAAGNhcHR1cmVzBwEAAAAAAAAAAgAAAAAAAABjMAsCAAAAAAAAAAQHAAAAAAAAAGNvbnRleHQEDAAAAAAAAABfaGNlNzI0MTdhYzAHAAAAAAAAAHByb2dyYW0E1gIAAAAAAAB7InZlcnNpb24iOjEsIm5vZGVzIjpbeyJvcCI6ImNhcHR1cmUiLCJ0eXBlIjp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiKGRhcnQ6Y29yZSNTdHJpbmcsZGFydDpjb3JlI09iamVjdCktPnZvaWQifSwibmFtZSI6ImMwIn0seyJvcCI6Im5hdGl2ZS5jYWxsIiwidHlwZSI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6ImZsdXR0ZXIuR2VzdHVyZVRhcE1vdmVDYWxsYmFjayJ9LCJpbnB1dHMiOlswXSwidmFsdWUiOnsiYmluZGluZyI6Il9oMTk5Y2EyYmFjMyIsImNvbnRyYWN0Ijp7InR5cGUiOiJpbnN0YWxsZWQuY2FsbCIsIm51bGxhYmxlIjpmYWxzZSwiY2FsbCI6eyJpbnB1dHMiOlt7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiKGRhcnQ6Y29yZSNTdHJpbmcsZGFydDpjb3JlI09iamVjdCktPnZvaWQifV0sImNhcHR1cmVzIjp7fSwicmVzdWx0Ijp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiZmx1dHRlci5HZXN0dXJlVGFwTW92ZUNhbGxiYWNrIn0sImltcGxlbWVudGF0aW9uIjoiMTk5Y2EyYmFjM2NlN2UyOGNiNjQ5YWQ1MmI5NmFkYzhjMzFkODg3Njg4MzJiMzU3YzY5NTE2ZTAzYWQ5ZjFhNSJ9fSwiY2FwdHVyZXMiOnt9fX1dLCJyb290IjoxLCJjYXB0dXJlcyI6eyJjMCI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6IihkYXJ0OmNvcmUjU3RyaW5nLGRhcnQ6Y29yZSNPYmplY3QpLT52b2lkIn19LCJwYXJhbWV0ZXJzIjp7fX0HAAAAAAAAAHZlcnNpb24CAQAAAAAAAAAUAAAAAAAAAG9uVGFwTW92ZU1lYXN1cmVtZW50DhwAAAAAAAAAX19yZXN0YWdlX21lYXN1cmVtZW50X3RhcF92MQEAAAAAAAAAHgAAAAAAAABfX3Jlc3RhZ2VfbWVhc3VyZW1lbnRfcm91dGVfdjEENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwuTWU4aXJrc0RfRmRJR1IxNVpwNW9yZm5nTzlVV0U2bDIHAAAAAAAAAG9uVGFwVXALAgAAAAAAAAAEBwAAAAAAAABjb250ZXh0BAwAAAAAAAAAX2gwZTliN2U0M2RlEgAAAAAAAABvblRhcFVwTWVhc3VyZW1lbnQOHAAAAAAAAABfX3Jlc3RhZ2VfbWVhc3VyZW1lbnRfdGFwX3YxAQAAAAAAAAAeAAAAAAAAAF9fcmVzdGFnZV9tZWFzdXJlbWVudF9yb3V0ZV92MQQ2AAAAAAAAAG1ydjEuWldSblpTNW5aWE4wZFhKbC5YeEdjVmhmTTlpM3c3WXJ6bGJra0lDMHJLaXdXSjY0cxEAAAAAAAAAb25UZXJ0aWFyeVRhcERvd24HAwAAAAAAAAAIAAAAAAAAAGNhcHR1cmVzBwEAAAAAAAAAAgAAAAAAAABjMAsCAAAAAAAAAAQHAAAAAAAAAGNvbnRleHQEDAAAAAAAAABfaGNlNzI0MTdhYzAHAAAAAAAAAHByb2dyYW0E1gIAAAAAAAB7InZlcnNpb24iOjEsIm5vZGVzIjpbeyJvcCI6ImNhcHR1cmUiLCJ0eXBlIjp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiKGRhcnQ6Y29yZSNTdHJpbmcsZGFydDpjb3JlI09iamVjdCktPnZvaWQifSwibmFtZSI6ImMwIn0seyJvcCI6Im5hdGl2ZS5jYWxsIiwidHlwZSI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6ImZsdXR0ZXIuR2VzdHVyZVRhcERvd25DYWxsYmFjayJ9LCJpbnB1dHMiOlswXSwidmFsdWUiOnsiYmluZGluZyI6Il9oMDJhNzE0MTEzMyIsImNvbnRyYWN0Ijp7InR5cGUiOiJpbnN0YWxsZWQuY2FsbCIsIm51bGxhYmxlIjpmYWxzZSwiY2FsbCI6eyJpbnB1dHMiOlt7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiKGRhcnQ6Y29yZSNTdHJpbmcsZGFydDpjb3JlI09iamVjdCktPnZvaWQifV0sImNhcHR1cmVzIjp7fSwicmVzdWx0Ijp7ImtpbmQiOiJuYXRpdmUiLCJuYXRpdmVUeXBlIjoiZmx1dHRlci5HZXN0dXJlVGFwRG93bkNhbGxiYWNrIn0sImltcGxlbWVudGF0aW9uIjoiMDJhNzE0MTEzMzgxNWUwOWM1OWE5NWRkNjAxOWY1OWY4NjJkNDlhNTZhZmY5Zjc1ZGNhNjc1MzQ0NjNlYTBjMSJ9fSwiY2FwdHVyZXMiOnt9fX1dLCJyb290IjoxLCJjYXB0dXJlcyI6eyJjMCI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6IihkYXJ0OmNvcmUjU3RyaW5nLGRhcnQ6Y29yZSNPYmplY3QpLT52b2lkIn19LCJwYXJhbWV0ZXJzIjp7fX0HAAAAAAAAAHZlcnNpb24CAQAAAAAAAAAcAAAAAAAAAG9uVGVydGlhcnlUYXBEb3duTWVhc3VyZW1lbnQOHAAAAAAAAABfX3Jlc3RhZ2VfbWVhc3VyZW1lbnRfdGFwX3YxAQAAAAAAAAAeAAAAAAAAAF9fcmVzdGFnZV9tZWFzdXJlbWVudF9yb3V0ZV92MQQ2AAAAAAAAAG1ydjEuWldSblpTNW5aWE4wZFhKbC5BbXUzcjNIVm5IQVBpaWpGT1poQjlBd3NIWENHeE41Ug8AAAAAAAAAb25UZXJ0aWFyeVRhcFVwBwMAAAAAAAAACAAAAAAAAABjYXB0dXJlcwcBAAAAAAAAAAIAAAAAAAAAYzALAgAAAAAAAAAEBwAAAAAAAABjb250ZXh0BAwAAAAAAAAAX2hjZTcyNDE3YWMwBwAAAAAAAABwcm9ncmFtBNICAAAAAAAAeyJ2ZXJzaW9uIjoxLCJub2RlcyI6W3sib3AiOiJjYXB0dXJlIiwidHlwZSI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6IihkYXJ0OmNvcmUjU3RyaW5nLGRhcnQ6Y29yZSNPYmplY3QpLT52b2lkIn0sIm5hbWUiOiJjMCJ9LHsib3AiOiJuYXRpdmUuY2FsbCIsInR5cGUiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiJmbHV0dGVyLkdlc3R1cmVUYXBVcENhbGxiYWNrIn0sImlucHV0cyI6WzBdLCJ2YWx1ZSI6eyJiaW5kaW5nIjoiX2g5MTZhMmI4MTU5IiwiY29udHJhY3QiOnsidHlwZSI6Imluc3RhbGxlZC5jYWxsIiwibnVsbGFibGUiOmZhbHNlLCJjYWxsIjp7ImlucHV0cyI6W3sia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiIoZGFydDpjb3JlI1N0cmluZyxkYXJ0OmNvcmUjT2JqZWN0KS0+dm9pZCJ9XSwiY2FwdHVyZXMiOnt9LCJyZXN1bHQiOnsia2luZCI6Im5hdGl2ZSIsIm5hdGl2ZVR5cGUiOiJmbHV0dGVyLkdlc3R1cmVUYXBVcENhbGxiYWNrIn0sImltcGxlbWVudGF0aW9uIjoiOTE2YTJiODE1OTI1MGVhYTZhN2ZhNmMxNTcxM2NmZjVjNjg5ODZhZDZlZjAzYjU4ODk3YWRhMzM4NDA1MTZhZSJ9fSwiY2FwdHVyZXMiOnt9fX1dLCJyb290IjoxLCJjYXB0dXJlcyI6eyJjMCI6eyJraW5kIjoibmF0aXZlIiwibmF0aXZlVHlwZSI6IihkYXJ0OmNvcmUjU3RyaW5nLGRhcnQ6Y29yZSNPYmplY3QpLT52b2lkIn19LCJwYXJhbWV0ZXJzIjp7fX0HAAAAAAAAAHZlcnNpb24CAQAAAAAAAAAaAAAAAAAAAG9uVGVydGlhcnlUYXBVcE1lYXN1cmVtZW50DhwAAAAAAAAAX19yZXN0YWdlX21lYXN1cmVtZW50X3RhcF92MQEAAAAAAAAAHgAAAAAAAABfX3Jlc3RhZ2VfbWVhc3VyZW1lbnRfcm91dGVfdjEENgAAAAAAAABtcnYxLlpXUm5aUzVuWlhOMGRYSmwudk1pZWVJa09oc3pLYkxxUDhiSmZ2SXBLM2M0Rm5HOTgEAAAAAAAAAHRleHQEAwAAAAAAAABUYXALAAAAAAAAAHBvaW50VG9rZW5zBQcAAAAAAAAABCAAAAAAAAAAQW11M3IzSFZuSEFQaWlqRk9aaEI5QXdzSFhDR3hONVIEIAAAAAAAAABFNDBWdGpORjNfY3RsZUZSZHN2UnpFTmNHbmM4amFSUQQgAAAAAAAAAE1lOGlya3NEX0ZkSUdSMTVacDVvcmZuZ085VVdFNmwyBCAAAAAAAAAAWHhHY1ZoZk05aTN3N1lyemxia2tJQzByS2l3V0o2NHMEIAAAAAAAAAByVk5qNE1pNGhfUzNLWE41WXFhVUxUZFlYWnhwTkFlMwQgAAAAAAAAAHZNaWVlSWtPaHN6S2JMcVA4YkpmdklwSzNjNEZuRzk4BCAAAAAAAAAAd2VuTXVxajFZcnVDRndmbkNvUms3QlZHbGRZMXBaekI=";
Map<String, r.NativeBinding<Object?>> gestureMeasuredTapBindings(
        GestureTapScreen source) =>
    {
      "_h02a7141133": r.NativeBinding(
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
                  "02a7141133815e09c59a95dd6019f59f862d49a56aff9f75dca67534463ea0c1"
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
                      "02a7141133815e09c59a95dd6019f59f862d49a56aff9f75dca67534463ea0c1"
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
      "_h050972b7fa": r.NativeBinding(
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
                  "050972b7fa389c74fa647d7d3ea66e1495e9bf92a75a4f33e2cc91ffcbafcb11"
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
                      "050972b7fa389c74fa647d7d3ea66e1495e9bf92a75a4f33e2cc91ffcbafcb11"
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
      "_h0e9b7e43de": r.NativeBinding(
          contract: s.NativeBindingContract(
              type: 'flutter.GestureTapUpCallback', nullable: false),
          value: source.up),
      "_h199ca2bac3": r.NativeBinding(
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
                  "199ca2bac3ce7e28cb649ad52b96adc8c31d88768832b357c69516e03ad9f1a5"
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
                      "199ca2bac3ce7e28cb649ad52b96adc8c31d88768832b357c69516e03ad9f1a5"
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
      "_h49a4341324": r.NativeBinding(
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
                  "49a4341324bc1b08ced19ba80bcc61a5522b39626cda8c6c0b0cdd3f5095e139"
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
                      "49a4341324bc1b08ced19ba80bcc61a5522b39626cda8c6c0b0cdd3f5095e139"
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
      "_h916a2b8159": r.NativeBinding(
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
                  "916a2b8159250eaa6a7fa6c15713cff5c68986ad6ef03b58897ada33840516ae"
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
                      "916a2b8159250eaa6a7fa6c15713cff5c68986ad6ef03b58897ada33840516ae"
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
      "_hce72417ac0": r.NativeBinding(
          contract: s.NativeBindingContract(
              type: '(dart:core#String,dart:core#Object)->void',
              nullable: false),
          value: source.seen),
      "_he3b10b6945": r.NativeBinding(
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
                  "e3b10b6945e27529e36916aa0b01ff05cce6137ff210c2089e25c798ff908e97"
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
                      "e3b10b6945e27529e36916aa0b01ff05cce6137ff210c2089e25c798ff908e97"
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
    };
Map<String, Object?> gestureMeasuredTapContext() => {
      "_h02a7141133": {
        "kind": "nativeBinding",
        "key": "_h02a7141133",
        "type": "installed.call",
        "nullable": false
      },
      "_h050972b7fa": {
        "kind": "nativeBinding",
        "key": "_h050972b7fa",
        "type": "installed.call",
        "nullable": false
      },
      "_h0e9b7e43de": {
        "kind": "nativeBinding",
        "key": "_h0e9b7e43de",
        "type": "flutter.GestureTapUpCallback",
        "nullable": false
      },
      "_h199ca2bac3": {
        "kind": "nativeBinding",
        "key": "_h199ca2bac3",
        "type": "installed.call",
        "nullable": false
      },
      "_h49a4341324": {
        "kind": "nativeBinding",
        "key": "_h49a4341324",
        "type": "installed.call",
        "nullable": false
      },
      "_h916a2b8159": {
        "kind": "nativeBinding",
        "key": "_h916a2b8159",
        "type": "installed.call",
        "nullable": false
      },
      "_hce72417ac0": {
        "kind": "nativeBinding",
        "key": "_hce72417ac0",
        "type": "(dart:core#String,dart:core#Object)->void",
        "nullable": false
      },
      "_he3b10b6945": {
        "kind": "nativeBinding",
        "key": "_he3b10b6945",
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
