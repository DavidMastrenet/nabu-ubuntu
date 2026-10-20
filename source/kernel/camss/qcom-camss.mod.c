#include <linux/module.h>
#include <linux/export-internal.h>
#include <linux/compiler.h>

MODULE_INFO(name, KBUILD_MODNAME);

__visible struct module __this_module
__section(".gnu.linkonce.this_module") = {
	.name = KBUILD_MODNAME,
	.init = init_module,
#ifdef CONFIG_MODULE_UNLOAD
	.exit = cleanup_module,
#endif
	.arch = MODULE_ARCH_INIT,
};


MODULE_INFO(depends, "");

MODULE_ALIAS("of:N*T*Cqcom,msm8916-camss");
MODULE_ALIAS("of:N*T*Cqcom,msm8916-camssC*");
MODULE_ALIAS("of:N*T*Cqcom,msm8953-camss");
MODULE_ALIAS("of:N*T*Cqcom,msm8953-camssC*");
MODULE_ALIAS("of:N*T*Cqcom,msm8996-camss");
MODULE_ALIAS("of:N*T*Cqcom,msm8996-camssC*");
MODULE_ALIAS("of:N*T*Cqcom,sc7280-camss");
MODULE_ALIAS("of:N*T*Cqcom,sc7280-camssC*");
MODULE_ALIAS("of:N*T*Cqcom,sc8280xp-camss");
MODULE_ALIAS("of:N*T*Cqcom,sc8280xp-camssC*");
MODULE_ALIAS("of:N*T*Cqcom,sdm660-camss");
MODULE_ALIAS("of:N*T*Cqcom,sdm660-camssC*");
MODULE_ALIAS("of:N*T*Cqcom,sdm845-camss");
MODULE_ALIAS("of:N*T*Cqcom,sdm845-camssC*");
MODULE_ALIAS("of:N*T*Cqcom,sm8150-camss");
MODULE_ALIAS("of:N*T*Cqcom,sm8150-camssC*");
MODULE_ALIAS("of:N*T*Cqcom,sm8250-camss");
MODULE_ALIAS("of:N*T*Cqcom,sm8250-camssC*");
