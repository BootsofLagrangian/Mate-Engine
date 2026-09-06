import math
import struct
import unittest
from bake_humanoid import bake,base


class HelperBakeTests(unittest.TestCase):
    def test_dynamic_unmapped_parent_is_folded_into_head(self):
        binary=struct.pack('<10f',0,1,0,0,0,1,0,0,math.sin(math.pi/4),math.cos(math.pi/4))
        data={'nodes':[{'name':'Hip','translation':[0,.9,0],'children':[1]},
                       {'name':'Control','children':[2]}, {'name':'Head','translation':[0,.5,0]}],
              'accessors':[{'bufferView':0,'componentType':5126,'count':2,'type':'SCALAR'},
                           {'bufferView':1,'componentType':5126,'count':2,'type':'VEC4'}],
              'bufferViews':[{'byteOffset':0,'byteLength':8},{'byteOffset':8,'byteLength':32}],
              'animations':[{'channels':[{'target':{'node':1,'path':'rotation'},'sampler':0}],
                             'samplers':[{'input':0,'output':1}]}]}
        blob,report=bake(data,binary,{'Hip':'hips','Head':'head'},2)
        out,packed=base.read_glb(blob)
        self.assertEqual(report['mapped_bones'],2)
        self.assertEqual(out['nodes'][0]['children'],[1])
        self.assertAlmostEqual(out['nodes'][0]['translation'][1],1.8)
        self.assertAlmostEqual(out['nodes'][1]['translation'][1],1)
        animation=out['animations'][0]
        channel=next(c for c in animation['channels'] if c['target']=={'node':1,'path':'rotation'})
        accessor=out['accessors'][animation['samplers'][channel['sampler']]['output']]
        view=out['bufferViews'][accessor['bufferView']]
        final=struct.unpack_from('<4f',packed,view['byteOffset']+(accessor['count']-1)*16)
        self.assertAlmostEqual(final[2],math.sin(math.pi/4),places=6)
        self.assertAlmostEqual(final[3],math.cos(math.pi/4),places=6)


if __name__=='__main__':
    unittest.main()
