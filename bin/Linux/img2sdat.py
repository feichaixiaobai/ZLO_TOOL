#!/usr/bin/env python
# -*- coding: utf-8 -*-
#====================================================
#          FILE: img2sdat.py
#       AUTHORS: xpirt - luxi78 - howellzhu
#          DATE: 2018-05-25 12:19:12 CEST
#====================================================

from __future__ import print_function

import sys, os, errno, tempfile

# 设置环境变量，确保使用UTF-8编码
if sys.platform == 'win32':
    os.environ['PYTHONIOENCODING'] = 'utf-8'

# 尝试导入依赖模块
try:
    import common, blockimgdiff, sparse_img
except ImportError as e:
    print("错误: 缺少必要的依赖模块")
    print("img2sdat.py 需要以下模块: common, blockimgdiff, sparse_img")
    print("这些模块通常来自 Android sdat2img 工具集")
    print("请确保这些模块在 Python 路径中，或使用完整的 sdat2img 工具集")
    if sys.version_info >= (3, 0):
        print("详细错误: {}".format(e))
    else:
        print("详细错误: %s" % str(e))
    sys.exit(1)

def main(INPUT_IMAGE, OUTDIR='.', VERSION=None, PREFIX='system'):
    global input

    __version__ = '1.7'

    if sys.hexversion < 0x02070000:
        print >> sys.stderr, "Python 2.7 or newer is required."
        try:
            input = raw_input
        except NameError: pass
        input('Press ENTER to exit...')
        sys.exit(1)
    else:
        print('img2sdat binary - version: %s\n' % __version__)
        
    if not os.path.isdir(OUTDIR):
        os.makedirs(OUTDIR)

    OUTDIR = OUTDIR + '/'+ PREFIX

    if not VERSION:
        VERSION = 4
        while True:
            print('''            1. Android Lollipop 5.0
            2. Android Lollipop 5.1
            3. Android Marshmallow 6.0
            4. Android Nougat 7.0/7.1/8.0/8.1
            ''')
            try:
                input = raw_input
            except NameError: pass
            item = input('Choose system version: ')
            if item == '1':
                VERSION = 1
                break
            elif item == '2':
                VERSION = 2
                break
            elif item == '3':
                VERSION = 3
                break
            elif item == '4':
                VERSION = 4
                break
            else:
                return

    # Get sparse image
    image = sparse_img.SparseImage(INPUT_IMAGE, tempfile.mkstemp()[1], '0')

    # Generate output files
    b = blockimgdiff.BlockImageDiff(image, None, VERSION)
    b.Compute(OUTDIR)

    print('Done! Output files: %s' % os.path.dirname(OUTDIR))
    return

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Visit xda thread for more information.')
    parser.add_argument('image', help='input system image')
    parser.add_argument('-o', '--outdir', help='output directory (current directory by default)')
    parser.add_argument('-v', '--version', help='transfer list version number, will be asked by default - more info on xda thread)')
    parser.add_argument('-p', '--prefix', help='name of image (prefix.new.dat)')

    args = parser.parse_args()

    INPUT_IMAGE = args.image
    
    if args.outdir:
        OUTDIR = args.outdir
    else:
        OUTDIR = '.'

    if args.version:
        VERSION = int(args.version)
    else:
        VERSION = None
    
    if args.prefix:
        PREFIX = args.prefix
    else:
        PREFIX = 'system'
    
    main(INPUT_IMAGE, OUTDIR, VERSION, PREFIX)
