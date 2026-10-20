// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Xiaomi nabu CN3927 VCM. Register sequence and travel limits are from
 * com.qti.sensormodule.nabu_ofilm_ov13b10.bin (see oem-actuator.json).
 * Copyright (C) 2026 洪宇轩 <yuxuan.hong@ieee.org>
 */
#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/pm_runtime.h>
#include <linux/regulator/consumer.h>
#include <media/v4l2-ctrls.h>
#include <media/v4l2-device.h>

#define CN3927_MIN 253
#define CN3927_MAX 733

struct cn3927 {
	struct v4l2_subdev sd;
	struct v4l2_ctrl_handler ctrls;
	struct regulator_bulk_data supplies[2];
	u16 position;
};

static int cn3927_write(struct i2c_client *client, u8 reg, u8 val)
{
	u8 data[] = { reg, val };
	int ret = i2c_master_send(client, data, sizeof(data));

	return ret == sizeof(data) ? 0 : ret < 0 ? ret : -EIO;
}

static int cn3927_position(struct i2c_client *client, u16 position)
{
	u8 data[] = { 0x03, (position >> 8) & 0x03, position & 0xff };
	int ret = i2c_master_send(client, data, sizeof(data));

	return ret == sizeof(data) ? 0 : ret < 0 ? ret : -EIO;
}

static struct cn3927 *to_cn3927(struct device *dev)
{
	return container_of(i2c_get_clientdata(to_i2c_client(dev)),
			    struct cn3927, sd);
}

static int cn3927_resume(struct device *dev)
{
	struct cn3927 *vcm = to_cn3927(dev);
	struct i2c_client *client = to_i2c_client(dev);
	static const u8 init[][2] = {
		{ 0xed, 0xab }, { 0x02, 0x01 }, { 0x02, 0x00 },
		{ 0x06, 0x84 }, { 0x07, 0x01 }, { 0x08, 0x59 },
	};
	int ret, i;

	ret = regulator_bulk_enable(ARRAY_SIZE(vcm->supplies), vcm->supplies);
	if (ret)
		return ret;
	usleep_range(1000, 1500);
	for (i = 0; i < ARRAY_SIZE(init); i++) {
		ret = cn3927_write(client, init[i][0], init[i][1]);
		if (ret)
			goto power_off;
		if (i == 2)
			usleep_range(100, 150);
	}
	ret = cn3927_position(client, vcm->position);
	if (!ret)
		return 0;
power_off:
	regulator_bulk_disable(ARRAY_SIZE(vcm->supplies), vcm->supplies);
	return ret;
}

static int cn3927_suspend(struct device *dev)
{
	struct cn3927 *vcm = to_cn3927(dev);
	struct i2c_client *client = to_i2c_client(dev);
	int position;

	for (position = vcm->position; position > 0; position -= 16) {
		if (cn3927_position(client, position))
			break;
		usleep_range(1000, 1100);
	}
	cn3927_position(client, 0);
	cn3927_write(client, 0x02, 0x01);
	return regulator_bulk_disable(ARRAY_SIZE(vcm->supplies), vcm->supplies);
}

static int cn3927_ctrl(struct v4l2_ctrl *ctrl)
{
	struct cn3927 *vcm = container_of(ctrl->handler, struct cn3927, ctrls);
	struct device *dev = vcm->sd.dev;
	int ret;

	if (ctrl->id != V4L2_CID_FOCUS_ABSOLUTE)
		return -EINVAL;
	ret = pm_runtime_get_if_in_use(dev);
	if (ret < 0)
		return ret;
	if (!ret) {
		vcm->position = ctrl->val;
		return 0;
	}
	ret = cn3927_position(to_i2c_client(dev), ctrl->val);
	if (!ret)
		vcm->position = ctrl->val;
	pm_runtime_put(dev);
	return ret;
}

static int cn3927_open(struct v4l2_subdev *sd, struct v4l2_subdev_fh *fh)
{
	return pm_runtime_resume_and_get(sd->dev);
}

static int cn3927_close(struct v4l2_subdev *sd, struct v4l2_subdev_fh *fh)
{
	pm_runtime_put(sd->dev);
	return 0;
}

static const struct v4l2_ctrl_ops cn3927_ctrl_ops = { .s_ctrl = cn3927_ctrl };
static const struct v4l2_subdev_ops cn3927_ops = {};
static const struct v4l2_subdev_internal_ops cn3927_internal_ops = {
	.open = cn3927_open, .close = cn3927_close,
};

static int cn3927_probe(struct i2c_client *client)
{
	struct cn3927 *vcm;
	int ret;

	vcm = devm_kzalloc(&client->dev, sizeof(*vcm), GFP_KERNEL);
	if (!vcm)
		return -ENOMEM;
	vcm->supplies[0].supply = "vddio";
	vcm->supplies[1].supply = "vdd";
	ret = devm_regulator_bulk_get(&client->dev,
				     ARRAY_SIZE(vcm->supplies), vcm->supplies);
	if (ret)
		return dev_err_probe(&client->dev, ret, "supplies\n");
	vcm->position = CN3927_MIN;
	v4l2_i2c_subdev_init(&vcm->sd, client, &cn3927_ops);
	vcm->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	vcm->sd.internal_ops = &cn3927_internal_ops;
	v4l2_ctrl_handler_init(&vcm->ctrls, 1);
	v4l2_ctrl_new_std(&vcm->ctrls, &cn3927_ctrl_ops,
			 V4L2_CID_FOCUS_ABSOLUTE, CN3927_MIN, CN3927_MAX, 1,
			 CN3927_MIN);
	vcm->sd.ctrl_handler = &vcm->ctrls;
	ret = vcm->ctrls.error;
	if (ret)
		goto free_controls;
	ret = media_entity_pads_init(&vcm->sd.entity, 0, NULL);
	if (ret)
		goto free_controls;
	vcm->sd.entity.function = MEDIA_ENT_F_LENS;
	pm_runtime_set_suspended(&client->dev);
	pm_runtime_enable(&client->dev);
	ret = v4l2_async_register_subdev(&vcm->sd);
	if (!ret)
		return 0;
	pm_runtime_disable(&client->dev);
	media_entity_cleanup(&vcm->sd.entity);
free_controls:
	v4l2_ctrl_handler_free(&vcm->ctrls);
	return ret;
}

static void cn3927_remove(struct i2c_client *client)
{
	struct cn3927 *vcm = to_cn3927(&client->dev);

	v4l2_async_unregister_subdev(&vcm->sd);
	pm_runtime_disable(&client->dev);
	if (!pm_runtime_status_suspended(&client->dev))
		cn3927_suspend(&client->dev);
	pm_runtime_set_suspended(&client->dev);
	v4l2_ctrl_handler_free(&vcm->ctrls);
	media_entity_cleanup(&vcm->sd.entity);
}

static const struct of_device_id cn3927_of_match[] = {
	{ .compatible = "chipnext,cn3927" }, {}
};
MODULE_DEVICE_TABLE(of, cn3927_of_match);
static const struct dev_pm_ops cn3927_pm = {
	SET_RUNTIME_PM_OPS(cn3927_suspend, cn3927_resume, NULL)
	SET_SYSTEM_SLEEP_PM_OPS(pm_runtime_force_suspend, pm_runtime_force_resume)
};
static struct i2c_driver cn3927_driver = {
	.driver = {
		.name = "cn3927", .of_match_table = cn3927_of_match,
		.pm = &cn3927_pm,
	},
	.probe = cn3927_probe,
	.remove = cn3927_remove,
};
module_i2c_driver(cn3927_driver);
MODULE_DESCRIPTION("Xiaomi nabu CN3927 lens actuator");
MODULE_AUTHOR("洪宇轩 <yuxuan.hong@ieee.org>");
MODULE_LICENSE("GPL");
