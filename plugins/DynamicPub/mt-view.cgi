#!/usr/bin/perl -w

# Movable Type (r) Open Source (C) 2001-2008 Six Apart, Ltd.
# This program is distributed under the terms of the
# GNU General Public License, version 2.
#
# $Id: mt-view.cgi 1174 2008-01-08 21:02:50Z bchoate $

use strict;
use lib $ENV{MT_HOME} ? "$ENV{MT_HOME}/lib" : '../../lib';
use lib $ENV{MT_HOME} ? "$ENV{MT_HOME}/extlib" : '../../extlib';
use lib $ENV{MT_HOME} ? "$ENV{MT_HOME}/plugins/DynamicPub/lib" : '../../plugins/DynamicPub/lib';
# print "Content-type: text/plain\n\n";
# print join(", ", @INC);
use MT::Bootstrap App => 'MT::App::Viewer';
