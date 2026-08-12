# 机器人定位融合交付

将输入数据包解压后，在MATLAB中把output/src加入路径，再调用run_oosm_localization。第一个参数指向input_data，第二个参数指向可写output目录。

程序按量测到达顺序推进定位状态，延迟量测在固定滞后窗内回放。results目录记录状态轨迹、事件裁决、创新量和回放范围，figures目录提供轨迹图。

Windows11可使用原生MATLAB运行。输入目录应保持只读，输出目录需要创建、删除和重命名文件的权限。
