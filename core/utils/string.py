#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import base64


def string_to_base64(text):
    return str(base64.b64encode(str(text).encode("utf-8")), "utf-8")

def to_camel_case(string):
    components = string.split('_')
    return components[0] + ''.join(x.title() for x in components[1:])
