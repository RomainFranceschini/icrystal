import unittest
import jupyter_kernel_test


class MyKernelTests(jupyter_kernel_test.KernelTests):

    # The name identifying an installed kernel to run the tests against
    kernel_name = "crystal"

    # language_info.name in a kernel_info_reply should match this
    language_name = "Crystal"


if __name__ == '__main__':
    unittest.main()
