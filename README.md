
emqx-dashboard
==============

Dashboard for the EMQ Broker.

Build
-----

make && make ct

Configurtion
------------

```
dashboard.listener = 18083

dashboard.listener.acceptors = 2

dashboard.listener.max_clients = 512
```

Load Plugin
-----------

```
./bin/emqx_ctl plugins load emqx_dashboard
```

Login
-----

URL: http://host:18083

Username: admin

Password: public

License
-------

Apache License Version 2.0
