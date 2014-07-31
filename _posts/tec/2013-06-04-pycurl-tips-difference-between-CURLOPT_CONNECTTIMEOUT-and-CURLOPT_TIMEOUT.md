---
layout:     post
title:      PyCurl Tips
category: tec
description: PyCurl Tips
tags: pycurl tips timeout
---
Timeouts:

`CURLOPT_CONNECTTIMEOUT` is the maximum amount of time in seconds that is allowed to make the connection to the server.It can be set to 0 to disable this limit.

`CURLOPT_TIMEOUT` is a maximum amount of time in seconds to which the execution of individual cURL extension function calls will be limited.

**Note that the value for this setting should include the value for `CURLOPT_CONNECTTIMEOUT`**.

In other words, `CURLOPT_CONNECTTIMEOUT` is a segment of the time represented by `CURLOPT_TIMEOUT`, so the value of the `CURLOPT_TIMEOUT` should be greater than the value of the `CURLOPT_CONNECTTIMEOUT`.

See **pycurl.c** in `src/pycurl.c`:

	insint_c(d, "TIMEOUT", CURLOPT_TIMEOUT);
	insint_c(d, "CONNECTTIMEOUT", CURLOPT_CONNECTTIMEOUT);

You can see TIMEOUT in pycurl equals CURLOPT_TIMEOUT in curl, so does CONNECTTIMEOUT, it equals to CURLOPT_CONNECTTIMEOUT.
