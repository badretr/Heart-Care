# Captures demandées (section 26)

Les huit captures exigées par le cahier des charges, avec le lien direct et
**ce qu'il faut rendre visible** sur chacune. Une capture qui ne montre pas le
point attendu ne vaut pas la peine d'être prise.

Région : `us-east-1`. Vérifier que la session Learner Lab est ouverte avant de
commencer.

---

## 1. Pipeline avec fmt, validate et plan réussis

**Lien :** https://github.com/badretr/Heart-Care/actions

**Prendre :** la page d'un run **vert**, vue *Summary*.

**Doit montrer :**
- `Status: Success` et la durée ;
- les cinq jobs dans la colonne de gauche : les trois `Verifier et planifier`
  (dev, test, prod) en vert, `Appliquer (dev)` en vert ;
- les artefacts (`3`), qui prouvent que les plans sont conservés.

**Bonus :** ouvrir un job et déplier l'étape *Terraform Plan* pour montrer le
plan lisible — c'est ce que demande explicitement la section 19.

---

## 2. VPC et sous-réseaux

**Lien :** https://console.aws.amazon.com/vpcconsole/home?region=us-east-1#VpcDetails:VpcId=vpc-0b7e077072c571b7d

**Prendre :** d'abord le détail du VPC, puis l'onglet **Subnets** filtré sur ce VPC.

**Doit montrer :**
- le CIDR `10.20.0.0/16` ;
- les **six** sous-réseaux avec leurs CIDR et leurs zones, pour rendre visible
  la répartition sur deux AZ :

| Sous-réseau | CIDR | Zone |
|---|---|---|
| heartcare-dev-public-1 | 10.20.1.0/24 | us-east-1a |
| heartcare-dev-public-2 | 10.20.2.0/24 | us-east-1b |
| heartcare-dev-private-app-1 | 10.20.11.0/24 | us-east-1a |
| heartcare-dev-private-app-2 | 10.20.12.0/24 | us-east-1b |
| heartcare-dev-private-db-1 | 10.20.21.0/24 | us-east-1a |
| heartcare-dev-private-db-2 | 10.20.22.0/24 | us-east-1b |

---

## 3. Load Balancer et Target Group sain

**Lien :** https://console.aws.amazon.com/ec2/home?region=us-east-1#LoadBalancers:

**Prendre :** deux captures.

1. La liste des Load Balancers → l'ALB en état **Active**, schéma
   *internet-facing*, dans deux zones.
2. **Target Groups** → l'onglet *Targets* : les deux cibles en **healthy**.

**Doit montrer :** le mot `healthy` sur les deux instances. C'est ce que
demande la section 21 (« le health check du Target Group doit devenir
Healthy »).

---

## 4. Auto Scaling Group et instances

**Lien :** https://console.aws.amazon.com/ec2/home?region=us-east-1#AutoScalingGroups:

**Prendre :** le détail de l'ASG `heartcare-dev-20261112153108273700000003`.

**Doit montrer :**
- *Desired / Minimum / Maximum capacity* ;
- l'onglet **Instance management** : deux instances `InService`, **une par
  zone** ;
- l'onglet **Activity**, qui garde la trace des remplacements — utile pour
  appuyer le test de panne.

---

## 5. RDS dans les sous-réseaux privés

**Lien :** https://console.aws.amazon.com/rds/home?region=us-east-1#database:id=heartcare-dev-db

**Prendre :** l'onglet **Connectivity & security**.

**Doit montrer :**
- **Publicly accessible : No** — c'est le point central ;
- le *Subnet group* et ses sous-réseaux `10.20.21.0/24` et `10.20.22.0/24` ;
- le VPC security group.

**Bonus :** l'onglet *Configuration* avec *Encryption : Enabled*.

---

## 6. Backend distant

**Lien :** https://s3.console.aws.amazon.com/s3/buckets/heartcare-terraform-state-342766168998?region=us-east-1

**Prendre :** deux captures.

1. L'onglet **Objects** : les clés `dev/`, `test/` et `prod/` — elles rendent
   visible la **séparation des états** exigée en 16.1.
2. L'onglet **Properties** : *Bucket Versioning : Enabled* et *Default
   encryption : AES256*.

**Doit montrer :** versioning + chiffrement. Ce sont deux des six exigences du
backend, et les seules qui se voient à l'écran.

---

## 7. Page Web accessible

**Lien :** http://hc2026111215045903000000000c-1236470897.us-east-1.elb.amazonaws.com/

**Prendre :** deux captures.

1. Le site Heart Care dans le navigateur, **avec l'URL de l'ALB visible dans
   la barre d'adresse**.
2. `/whoami` actualisé plusieurs fois, montrant **deux noms d'instance
   différents** — c'est le test de répartition de la section 22.

---

## 8. Résultat du test de panne

**Prendre :** le terminal pendant l'opération, et la console EC2.

Commandes, depuis `terraform/environments/dev` :

```bash
URL=$(terraform output -raw alb_url)
ASG=$(terraform output -raw autoscaling_group_name)

# Instances avant
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].Instances[].{Id:InstanceId,AZ:AvailabilityZone}' --output table

# Arrêt brutal
aws autoscaling terminate-instance-in-auto-scaling-group \
  --instance-id <id> --no-should-decrement-desired-capacity

# Le service répond-il pendant le remplacement ?
for i in $(seq 1 30); do curl -s -o /dev/null -w "%{http_code} " "$URL"; sleep 5; done
```

**Doit montrer :** la suite de `200` ininterrompue. C'est le résultat le plus
parlant du projet — trente requêtes, aucune perdue.

En parallèle, la console EC2 avec l'ancienne instance en `shutting-down` et la
nouvelle en `pending`.

---

## Ordre conseillé

Prendre 2 à 7 d'abord, à froid. Garder le test de panne (8) pour la fin : il
modifie l'infrastructure, et les identifiants d'instance changent ensuite.

Ne lancer `terraform destroy` qu'**après** avoir pris les huit captures.
