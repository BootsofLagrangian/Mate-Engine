"""Regression checks for sparse Unity curve reconstruction."""
import math
import unittest
from sample_unity_curves import sample


def key(time,value,slope=0):
    return {'time':time,'value':{'x':value},'inSlope':{'x':slope},'outSlope':{'x':slope}}


class HermiteTests(unittest.TestCase):
    def test_authored_ease_is_not_linear(self):
        keys = [key(0,0),key(1,1)]
        self.assertAlmostEqual(sample(keys,.25,'x')[0],.15625)
        self.assertEqual(sample(keys,-1,'x'),[0])
        self.assertEqual(sample(keys,1,'x'),[1])

    def test_slopes_have_time_units(self):
        # A constant 2 units/sec velocity over three seconds stays linear.
        keys = [key(0,0,2),key(3,6,2)]
        self.assertAlmostEqual(sample(keys,.75,'x')[0],1.5)

    def test_infinite_slope_is_step_until_exact_key(self):
        keys = [key(0,2,math.inf),key(1,9,math.inf)]
        self.assertEqual(sample(keys,.99,'x'),[2])
        self.assertEqual(sample(keys,1,'x'),[9])

    def test_weighted_curve_rejected_instead_of_silently_distorted(self):
        keys = [key(0,0),key(1,1)]
        keys[0]['weightedMode'] = 1
        with self.assertRaises(ValueError):
            sample(keys,.5,'x')


if __name__ == '__main__':
    unittest.main()
